defmodule SimpleMCP.CompatScenario424 do
  @moduledoc """
  The fixed exchange sequence behind the slice-424 byte-compatibility proof.

  Slice 424 adds standing instructions and prompts, both optional and off unless a server defines
  them. A server written the way every consuming app writes one today (`SimpleMCP.CompatServer`:
  it defines neither) must answer exactly as it did before, through `initialize`, `tools/list`,
  `prompts/list` and `prompts/get` alike. The last two answer method-not-found on a server with no
  prompts, and that answer is part of what is pinned.

  Every exchange goes through `SimpleMCP.Plug`, in the default session mode (with a session id
  supplied by the client, so every byte is deterministic) and in `stateless: true` mode, and once
  with a caller context on the connection. The fixtures in `test/fixtures/52e7f0c/` were captured
  from the library at commit 52e7f0c (the master this slice branched from), BEFORE any slice-424
  change, with:

      MIX_ENV=test mix run -e 'SimpleMCP.CompatScenario424.capture!("test/fixtures/52e7f0c")'
  """

  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.Plug, as: MCPPlug

  @session "compat-session-fixture-424"
  @accept "application/json, text/event-stream"
  @session_opts MCPPlug.init(server: SimpleMCP.CompatServer)
  @stateless_opts MCPPlug.init(server: SimpleMCP.CompatServer, stateless: true)

  @doc """
  Runs every exchange in order and returns its name, status, response headers and body.
  Headers keep the order the plug produced them.
  """
  @spec run() :: [%{name: String.t(), status: integer(), headers: list(), body: binary()}]
  def run do
    Enum.map(exchanges(), fn {name, opts, build} ->
      conn = MCPPlug.call(build.(), opts)
      %{name: name, status: conn.status, headers: conn.resp_headers, body: conn.resp_body}
    end)
  end

  @doc "An exchange's status and headers as the text the fixtures hold."
  @spec render_headers(%{status: integer(), headers: list()}) :: binary()
  def render_headers(%{status: status, headers: headers}) do
    lines = Enum.map(headers, fn {key, value} -> "#{key}: #{value}\n" end)
    IO.iodata_to_binary(["status: #{status}\n" | lines])
  end

  @doc "Writes every exchange to `dir` as `<name>.headers` and `<name>.body`."
  @spec capture!(Path.t()) :: :ok
  def capture!(dir) do
    File.mkdir_p!(dir)

    for exchange <- run() do
      File.write!(Path.join(dir, "#{exchange.name}.headers"), render_headers(exchange))
      File.write!(Path.join(dir, "#{exchange.name}.body"), exchange.body)
    end

    :ok
  end

  @review_arguments %{"name" => "review", "arguments" => %{"topic" => "receipts"}}

  defp exchanges do
    [
      # The default session mode, session id supplied by the client.
      {"01_initialize_2025_06_18", @session_opts,
       fn -> rpc("initialize", %{"protocolVersion" => "2025-06-18"}, 1) end},
      {"02_initialize_no_version", @session_opts, fn -> rpc("initialize", %{}, 2) end},
      {"03_initialize_unknown_version", @session_opts,
       fn -> rpc("initialize", %{"protocolVersion" => "1999-01-01"}, 3) end},
      {"04_initialized_notification", @session_opts,
       fn -> notification("notifications/initialized") end},
      {"05_tools_list", @session_opts, fn -> rpc("tools/list", %{}, 4) end},
      {"06_tools_call", @session_opts,
       fn -> rpc("tools/call", %{"name" => "greet", "arguments" => %{"name" => "MCP"}}, 5) end},
      {"07_prompts_list", @session_opts, fn -> rpc("prompts/list", %{}, 6) end},
      {"08_prompts_get", @session_opts, fn -> rpc("prompts/get", @review_arguments, 7) end},
      {"09_prompts_get_no_params", @session_opts, fn -> rpc("prompts/get", %{}, 8) end},
      {"10_prompts_list_unknown_session", @session_opts,
       fn -> rpc("prompts/list", %{}, 9, "compat-session-unknown-424") end},
      # The stateless mode: no session header, none created.
      {"11_stateless_initialize", @stateless_opts,
       fn -> stateless_rpc("initialize", %{"protocolVersion" => "2025-06-18"}, 10) end},
      {"12_stateless_tools_list", @stateless_opts,
       fn -> stateless_rpc("tools/list", %{}, 11) end},
      {"13_stateless_prompts_list", @stateless_opts,
       fn -> stateless_rpc("prompts/list", %{}, 12) end},
      {"14_stateless_prompts_get", @stateless_opts,
       fn -> stateless_rpc("prompts/get", @review_arguments, 13) end},
      # A caller context on the connection changes nothing for a server that does not use it.
      {"15_context_initialize", @stateless_opts,
       fn -> with_context(stateless_rpc("initialize", %{}, 14)) end},
      {"16_context_prompts_list", @stateless_opts,
       fn -> with_context(stateless_rpc("prompts/list", %{}, 15)) end}
    ]
  end

  defp rpc(method, params, id, session \\ @session) do
    put_req_header(session_post(method, params, id), "mcp-session-id", session)
  end

  defp stateless_rpc(method, params, id), do: session_post(method, params, id)

  defp session_post(method, params, id) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
  end

  defp notification(method) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "method" => method})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
    |> put_req_header("mcp-session-id", @session)
  end

  defp with_context(conn), do: assign(conn, :simple_mcp_context, %{user: "compat-caller"})
end
