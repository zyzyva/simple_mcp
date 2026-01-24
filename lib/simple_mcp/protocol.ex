defmodule SimpleMCP.Protocol do
  @moduledoc """
  Handles JSON-RPC 2.0 message parsing and MCP protocol logic.
  """

  alias SimpleMCP.{Session, Tool}

  # Supported MCP protocol versions
  @supported_versions ["2025-11-25", "2025-03-26"]
  @default_version "2025-11-25"

  # JSON-RPC 2.0 error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601

  @doc """
  Parses and validates a JSON-RPC 2.0 request.
  """
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
    {:ok, %{
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
  """
  def handle_message(message, server_module, session_id) do
    case message.method do
      "initialize" ->
        handle_initialize(message, server_module, session_id)

      "notifications/initialized" ->
        handle_initialized(session_id)

      "tools/list" ->
        handle_tools_list(message, server_module, session_id)

      "tools/call" ->
        handle_tools_call(message, server_module, session_id)

      "ping" ->
        handle_ping(message)

      _ ->
        error_response(message.id, @method_not_found, "Method not found: #{message.method}")
    end
  end

  defp handle_initialize(message, server_module, session_id) do
    {name, version} = server_module.server_info()

    # Negotiate protocol version with client
    client_version = Map.get(message.params, "protocolVersion", @default_version)
    negotiated_version = negotiate_version(client_version)

    Session.update(session_id, %{
      initialized: false,
      protocol_version: negotiated_version,
      client_info: Map.get(message.params, "clientInfo")
    })

    success_response(message.id, %{
      "protocolVersion" => negotiated_version,
      "serverInfo" => %{
        "name" => name,
        "version" => version
      },
      "capabilities" => %{
        "tools" => %{}
      }
    })
  end

  defp negotiate_version(client_version) do
    if client_version in @supported_versions do
      client_version
    else
      @default_version
    end
  end

  defp handle_initialized(session_id) do
    Session.update(session_id, %{initialized: true})
    # Notifications don't get responses
    :no_response
  end

  defp handle_tools_list(message, server_module, session_id) do
    case Session.get(session_id) do
      nil ->
        error_response(message.id, @invalid_request, "Server not initialized")

      _session ->
        tools = server_module.tools()
        tool_list = Enum.map(tools, &Tool.to_mcp_format/1)
        success_response(message.id, %{"tools" => tool_list})
    end
  end

  defp handle_tools_call(message, server_module, session_id) do
    case Session.get(session_id) do
      nil ->
        error_response(message.id, @invalid_request, "Server not initialized")

      _session ->
        tool_name = Map.get(message.params, "name")
        arguments = Map.get(message.params, "arguments", %{})

        case server_module.handle_tool_call(tool_name, arguments) do
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
