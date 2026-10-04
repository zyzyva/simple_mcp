defmodule SimpleMCP.Protocol do
  @moduledoc """
  Handles JSON-RPC 2.0 message parsing and MCP protocol logic.
  """

  alias SimpleMCP.{Session, Tool}

  # Supported MCP protocol versions
  @supported_versions ["2025-11-25", "2025-06-18", "2025-03-26"]
  @default_version "2025-11-25"

  # JSON-RPC 2.0 error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601

  @type message :: %{id: term(), method: String.t(), params: map()}

  @doc """
  Parses and validates a JSON-RPC 2.0 request.
  """
  @spec parse_request(binary() | map()) :: {:ok, message()} | {:error, integer(), String.t()}
  def parse_request(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, message} -> validate_jsonrpc(message)
      {:error, _} -> {:error, @parse_error, "Parse error"}
    end
  end

  # Handle already-parsed body (when Phoenix parses JSON before our plug)
  def parse_request(body) when is_map(body) do
    validate_jsonrpc(body)
  end

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => method} = msg) do
    {:ok,
     %{
       id: Map.get(msg, "id"),
       method: method,
       params: Map.get(msg, "params", %{})
     }}
  end

  defp validate_jsonrpc(_) do
    {:error, @invalid_request, "Invalid JSON-RPC 2.0 request"}
  end

  @doc """
  Handles an MCP message and returns a response.

  Options:

    * `:stateless` - when `true`, no session is read, created or written, and
      `tools/list` and `tools/call` need none. Defaults to `false`.
    * `:context` - the value handed to a server's three-argument
      `handle_tool_call/3`. Defaults to `nil`.
  """
  @spec handle_message(message(), module(), String.t() | nil, keyword()) ::
          map() | :no_response
  def handle_message(message, server_module, session_id, opts \\ []) do
    request = %{
      stateless: Keyword.get(opts, :stateless, false),
      context: Keyword.get(opts, :context)
    }

    dispatch(message, server_module, session_id, request)
  end

  defp dispatch(message, server_module, session_id, request) do
    case message.method do
      "initialize" ->
        handle_initialize(message, server_module, session_id, request)

      "notifications/initialized" ->
        handle_initialized(session_id, request)

      "tools/list" ->
        handle_tools_list(message, server_module, session_id, request)

      "tools/call" ->
        handle_tools_call(message, server_module, session_id, request)

      "ping" ->
        handle_ping(message)

      _ ->
        error_response(message.id, @method_not_found, "Method not found: #{message.method}")
    end
  end

  defp handle_initialize(message, server_module, session_id, request) do
    negotiated_version = negotiate_client_version(message)
    maybe_update_session_on_initialize(session_id, negotiated_version, message, request)
    success_response(message.id, initialize_result(server_module, negotiated_version))
  end

  defp maybe_update_session_on_initialize(_session_id, _version, _message, %{stateless: true}),
    do: :ok

  defp maybe_update_session_on_initialize(session_id, version, message, _request) do
    update_session_on_initialize(session_id, version, message)
  end

  defp negotiate_client_version(message) do
    client_version = Map.get(message.params, "protocolVersion", @default_version)
    negotiate_version(client_version)
  end

  defp update_session_on_initialize(session_id, negotiated_version, message) do
    Session.update(session_id, %{
      initialized: false,
      protocol_version: negotiated_version,
      client_info: Map.get(message.params, "clientInfo")
    })
  end

  defp initialize_result(server_module, negotiated_version) do
    {name, version} = server_module.server_info()

    %{
      "protocolVersion" => negotiated_version,
      "serverInfo" => %{
        "name" => name,
        "version" => version
      },
      "capabilities" => %{
        "tools" => %{}
      }
    }
  end

  defp negotiate_version(client_version) do
    if client_version in @supported_versions do
      client_version
    else
      @default_version
    end
  end

  defp handle_initialized(_session_id, %{stateless: true}), do: :no_response

  defp handle_initialized(session_id, _request) do
    Session.update(session_id, %{initialized: true})
    # Notifications don't get responses
    :no_response
  end

  defp handle_tools_list(message, server_module, session_id, request) do
    case session_known?(session_id, request) do
      false ->
        error_response(message.id, @invalid_request, "Server not initialized")

      true ->
        tools = server_module.tools()
        tool_list = Enum.map(tools, &Tool.to_mcp_format/1)
        success_response(message.id, %{"tools" => tool_list})
    end
  end

  defp handle_tools_call(message, server_module, session_id, request) do
    case session_known?(session_id, request) do
      false ->
        error_response(message.id, @invalid_request, "Server not initialized")

      true ->
        run_tool(message, server_module, request.context)
    end
  end

  defp run_tool(message, server_module, context) do
    tool_name = Map.get(message.params, "name")
    arguments = Map.get(message.params, "arguments", %{})

    case call_tool(server_module, tool_name, arguments, context) do
      {:ok, result} ->
        content = format_tool_result(result)
        success_response(message.id, %{"content" => content})

      {:error, reason} ->
        success_response(message.id, %{
          "content" => [%{"type" => "text", "text" => "Error: #{reason}"}],
          "isError" => true
        })
    end
  end

  defp session_known?(_session_id, %{stateless: true}), do: true
  defp session_known?(session_id, _request), do: Session.get(session_id) != nil

  # A server that defines the three-argument callback receives the caller's context
  # (slice 318). Any other server gets the two-argument call it always got.
  defp call_tool(server_module, tool_name, arguments, context) do
    call_tool(context_callback?(server_module), server_module, tool_name, arguments, context)
  end

  defp call_tool(true, server_module, tool_name, arguments, context) do
    server_module.handle_tool_call(tool_name, arguments, context)
  end

  defp call_tool(false, server_module, tool_name, arguments, _context) do
    server_module.handle_tool_call(tool_name, arguments)
  end

  defp context_callback?(server_module) do
    Code.ensure_loaded?(server_module) and
      function_exported?(server_module, :handle_tool_call, 3)
  end

  defp handle_ping(message) do
    success_response(message.id, %{})
  end

  defp format_tool_result(result) when is_binary(result) do
    [%{"type" => "text", "text" => result}]
  end

  defp format_tool_result(result) when is_map(result) or is_list(result) do
    [%{"type" => "text", "text" => JSON.encode!(result)}]
  end

  defp format_tool_result(result) do
    [%{"type" => "text", "text" => inspect(result)}]
  end

  @doc """
  Creates a success response.
  """
  @spec success_response(term(), term()) :: map()
  def success_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  @doc """
  Creates an error response.
  """
  @spec error_response(term(), integer(), String.t(), term()) :: map()
  def error_response(id, code, message, data \\ nil) do
    error = %{
      "code" => code,
      "message" => message
    }

    error = if data, do: Map.put(error, "data", data), else: error

    %{
      "jsonrpc" => "2.0",
      "id" => id || "err_#{:erlang.unique_integer([:positive])}",
      "error" => error
    }
  end
end
