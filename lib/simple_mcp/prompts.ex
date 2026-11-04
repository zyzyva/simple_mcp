defmodule SimpleMCP.Prompts do
  @moduledoc false
  # The answers behind `prompts/list` and `prompts/get` (slice 424, MCP 2025-06-18), as data:
  # `{:ok, result}` or `{:error, code, message}`. `SimpleMCP.Protocol` turns them into JSON-RPC
  # responses. Nothing here raises: a failure in a server's own callback is a JSON-RPC error
  # (-32603, with the detail logged and not sent), never a crash and never an HTTP 500.

  require Logger

  alias SimpleMCP.Prompt

  @invalid_params -32_602
  @internal_error -32_603

  @doc "Whether `server` offers prompts: it defines `prompts/0`."
  @spec offered?(module()) :: boolean()
  def offered?(server), do: callback?(server, :prompts, 0)

  @doc "The `prompts/list` result."
  @spec list(module()) :: {:ok, map()} | {:error, integer(), String.t()}
  def list(server) do
    guarded("listing prompts", "Internal error listing prompts", fn ->
      {:ok, %{"prompts" => Enum.map(server.prompts(), &Prompt.to_mcp_format/1)}}
    end)
  end

  @doc "The `prompts/get` result for a request's params and the caller's context."
  @spec get(module(), term(), term()) :: {:ok, map()} | {:error, integer(), String.t()}
  def get(server, params, context) do
    with {:ok, name, arguments} <- parse_params(params),
         {:ok, prompt} <- find(server, name),
         :ok <- check_required(prompt, arguments) do
      render(server, name, arguments, context)
    end
  end

  # --- the request ---------------------------------------------------------------

  defp parse_params(%{"name" => name} = params) when is_binary(name) do
    case Map.get(params, "arguments") do
      nil -> {:ok, name, %{}}
      arguments when is_map(arguments) -> {:ok, name, arguments}
      _other -> invalid_params("arguments must be an object")
    end
  end

  defp parse_params(_params), do: invalid_params("a prompt name is required")

  defp find(server, name) do
    result =
      guarded("looking up prompt #{inspect(name)}", "Internal error looking up prompt", fn ->
        {:ok, server.prompts()}
      end)

    with {:ok, prompts} <- result do
      case Enum.find(prompts, &(&1.name == name)) do
        nil -> {:error, @invalid_params, "Unknown prompt: #{name}"}
        prompt -> {:ok, prompt}
      end
    end
  end

  defp check_required(prompt, arguments) do
    case Prompt.missing_arguments(prompt, arguments) do
      [] ->
        :ok

      missing ->
        {:error, @invalid_params, "Missing required argument(s): #{Enum.join(missing, ", ")}"}
    end
  end

  defp invalid_params(reason), do: {:error, @invalid_params, "Invalid params: #{reason}"}

  # --- the render ----------------------------------------------------------------

  defp render(server, name, arguments, context) do
    case callback?(server, :get_prompt, 3) do
      true ->
        guarded("rendering prompt #{inspect(name)}", "Internal error rendering prompt", fn ->
          normalise(server.get_prompt(name, arguments, context))
        end)

      false ->
        {:error, @internal_error, "This server lists prompts but does not define get_prompt/3."}
    end
  end

  defp normalise({:ok, messages}) when is_list(messages), do: build(messages, nil)

  defp normalise({:ok, %{messages: messages} = result}) when is_list(messages) do
    build(messages, Map.get(result, :description))
  end

  defp normalise({:error, reason}) when is_binary(reason), do: {:error, @internal_error, reason}
  defp normalise({:error, reason}), do: {:error, @internal_error, inspect(reason)}
  defp normalise(_other), do: invalid_result()

  defp build(messages, description) do
    with {:ok, built} <- build_messages(messages) do
      put_description(%{"messages" => built}, description)
    end
  end

  defp build_messages(messages) do
    reduced =
      Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, built} ->
        case message(message) do
          {:ok, one} -> {:cont, {:ok, [one | built]}}
          :error -> {:halt, invalid_result()}
        end
      end)

    reverse_ok(reduced)
  end

  defp reverse_ok({:ok, built}), do: {:ok, Enum.reverse(built)}
  defp reverse_ok(error), do: error

  defp put_description(result, nil), do: {:ok, result}

  defp put_description(result, text) when is_binary(text),
    do: {:ok, Map.put(result, "description", text)}

  defp put_description(_result, _other), do: invalid_result()

  defp message(%{} = message) do
    with {:ok, role} <- role(field(message, :role)),
         {:ok, content} <- content(field(message, :content)) do
      {:ok, %{"role" => role, "content" => content}}
    end
  end

  defp message(_other), do: :error

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp role(role) when role in [:user, "user"], do: {:ok, "user"}
  defp role(role) when role in [:assistant, "assistant"], do: {:ok, "assistant"}
  defp role(_other), do: :error

  # A string is a text block. Any other content must be a map with a type (an image, audio, a
  # resource, a text block written out), passed through with its keys as strings.
  defp content(text) when is_binary(text), do: {:ok, %{"type" => "text", "text" => text}}

  defp content(%{} = block) do
    case Map.has_key?(block, :type) or Map.has_key?(block, "type") do
      true -> {:ok, stringify(block)}
      false -> :error
    end
  end

  defp content(_other), do: :error

  defp stringify(%{} = map),
    do: Map.new(map, fn {key, value} -> {key_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key), do: key

  defp invalid_result, do: {:error, @internal_error, "Invalid prompt result"}

  # --- failures in a server's own callback -----------------------------------------

  defp guarded(what, client_message, fun) do
    fun.()
  rescue
    exception ->
      log_failure(what, Exception.format(:error, exception, __STACKTRACE__))
      {:error, @internal_error, client_message}
  catch
    kind, reason ->
      log_failure(what, Exception.format(kind, reason, __STACKTRACE__))
      {:error, @internal_error, client_message}
  end

  defp log_failure(what, detail), do: Logger.error("SimpleMCP: #{what} failed: #{detail}")

  defp callback?(server, name, arity) do
    Code.ensure_loaded?(server) and function_exported?(server, name, arity)
  end
end
