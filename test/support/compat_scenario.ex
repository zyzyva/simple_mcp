defmodule SimpleMCP.CompatScenario do
  @moduledoc """
  The fixed exchange sequence behind the byte-compatibility proof (slice 318).

  Each exchange goes through `SimpleMCP.Plug` with the default options and a
  session id supplied by the client, so every byte it returns is deterministic.
  The fixtures in `test/fixtures/aa2017e/` were captured from the library at
  commit aa2017e, before any slice-318 change, by running `run/0` there.
  """

  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.Plug, as: MCPPlug

  @session "compat-session-fixture"
  @accept "application/json, text/event-stream"
  @opts MCPPlug.init(server: SimpleMCP.CompatServer)

  @doc """
  Runs every exchange in order and returns its name, status, response headers
  and body. Headers keep the order the plug produced them.
  """
  @spec run() :: [%{name: String.t(), status: integer(), headers: list(), body: binary()}]
  def run do
    Enum.map(exchanges(), fn {name, build} ->
      conn = MCPPlug.call(build.(), @opts)
      %{name: name, status: conn.status, headers: conn.resp_headers, body: conn.resp_body}
    end)
  end

  defp exchanges do
    [
      {"01_initialize", fn -> rpc("initialize", %{"protocolVersion" => "2025-03-26"}, 1) end},
      {"02_initialized_notification", fn -> notification("notifications/initialized") end},
      {"03_tools_list", fn -> rpc("tools/list", %{}, 2) end},
      {"04_tools_call_binary", fn -> call_tool("greet", %{"name" => "MCP"}, 3) end},
      {"05_tools_call_map", fn -> call_tool("add", %{"a" => 2, "b" => 3}, 4) end},
      {"06_tools_call_list", fn -> call_tool("list", %{}, 5) end},
      {"07_tools_call_other", fn -> call_tool("number", %{}, 6) end},
      {"08_tools_call_error", fn -> call_tool("missing", %{}, 7) end},
      {"09_ping", fn -> rpc("ping", %{}, 8) end},
      {"10_unknown_method", fn -> rpc("resources/list", %{}, 9) end},
      {"11_parse_error", fn -> raw_post("not json") end},
      {"12_unknown_session_header",
       fn -> rpc("tools/list", %{}, 10, "compat-session-unknown") end},
      {"13_not_acceptable", fn -> rpc("ping", %{}, 11, @session, "application/json") end},
      {"14_get", fn -> put_session(conn(:get, "/mcp"), @session) end},
      {"15_delete", fn -> put_session(conn(:delete, "/mcp"), @session) end},
      {"16_delete_without_session", fn -> conn(:delete, "/mcp") end}
    ]
  end

  defp rpc(method, params, id, session \\ @session, accept \\ @accept) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", accept)
    |> put_req_header("mcp-session-id", session)
  end

  defp notification(method) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "method" => method})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
    |> put_req_header("mcp-session-id", @session)
  end

  defp call_tool(name, arguments, id) do
    rpc("tools/call", %{"name" => name, "arguments" => arguments}, id)
  end

  defp raw_post(body) do
    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
  end

  defp put_session(conn, session), do: put_req_header(conn, "mcp-session-id", session)
end
