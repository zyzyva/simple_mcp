defmodule SimpleMCP.StatelessTest do
  @moduledoc """
  Slice 318 behaviour 1, opt in with `stateless: true`: the server never creates,
  stores, requires or returns an `Mcp-Session-Id`. Async is off because the store
  size is asserted, and the store is one shared ETS table.
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.{Plug, Session}

  @opts Plug.init(server: SimpleMCP.TestServer, stateless: true)
  @accept "application/json, text/event-stream"

  describe "stateless: true" do
    test "tools/list works with no session header and no earlier initialize" do
      conn = post_rpc("tools/list", %{}, 1)

      assert conn.status == 200
      assert %{"result" => %{"tools" => tools}} = JSON.decode!(conn.resp_body)
      assert length(tools) == 3
    end

    test "tools/call works with no session header and no earlier initialize" do
      conn = post_rpc("tools/call", %{"name" => "greet", "arguments" => %{"name" => "A"}}, 2)

      assert conn.status == 200

      assert %{"result" => %{"content" => [%{"text" => "Hello, A!"}]}} =
               JSON.decode!(conn.resp_body)
    end

    test "initialize answers without returning a session" do
      conn = post_rpc("initialize", %{"protocolVersion" => "2025-03-26"}, 3)

      assert conn.status == 200
      assert get_resp_header(conn, "mcp-session-id") == []
      assert %{"result" => %{"protocolVersion" => "2025-03-26"}} = JSON.decode!(conn.resp_body)
    end

    test "a notification gets 202 with no session header" do
      conn =
        post_body(JSON.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}))

      assert conn.status == 202
      assert get_resp_header(conn, "mcp-session-id") == []
    end

    test "GET and DELETE answer 405" do
      get_conn = Plug.call(conn(:get, "/mcp"), @opts)

      delete_conn =
        Plug.call(put_req_header(conn(:delete, "/mcp"), "mcp-session-id", "any"), @opts)

      assert get_conn.status == 405
      assert delete_conn.status == 405
    end

    test "a session header sent anyway is served normally and not echoed" do
      conn = post_rpc("tools/list", %{}, 4, "random-client-session")

      assert conn.status == 200
      assert get_resp_header(conn, "mcp-session-id") == []
      assert %{"result" => %{"tools" => _}} = JSON.decode!(conn.resp_body)
    end

    test "the session store is never written" do
      session_id = "stateless-never-stored"
      before_size = :ets.info(:simple_mcp_sessions, :size)

      post_rpc("initialize", %{}, 5, session_id)
      post_rpc("tools/list", %{}, 6, session_id)
      post_rpc("tools/call", %{"name" => "greet", "arguments" => %{"name" => "B"}}, 7)
      post_body(JSON.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}))

      assert :ets.info(:simple_mcp_sessions, :size) == before_size
      assert Session.get(session_id) == nil
    end
  end

  defp post_rpc(method, params, id, session_id \\ nil) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id})
    post_body(body, session_id)
  end

  defp post_body(body, session_id \\ nil) do
    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
    |> maybe_put_session(session_id)
    |> Plug.call(@opts)
  end

  defp maybe_put_session(conn, nil), do: conn
  defp maybe_put_session(conn, session_id), do: put_req_header(conn, "mcp-session-id", session_id)
end
