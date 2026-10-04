defmodule SimpleMCP.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.Plug, as: MCPPlug

  @opts MCPPlug.init(server: SimpleMCP.TestServer)

  describe "POST /mcp" do
    test "handles initialize request" do
      body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2025-03-26",
            "clientInfo" => %{"name" => "test", "version" => "1.0"}
          },
          "id" => 1
        })

      conn = conn(:post, "/mcp", body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> MCPPlug.call(@opts)

      assert conn.status == 200
      assert get_resp_header(conn, "mcp-session-id") != []

      response = JSON.decode!(conn.resp_body)
      assert response["result"]["serverInfo"]["name"] == "Test Server"
    end

    test "returns error without proper Accept header" do
      body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "initialize",
          "params" => %{},
          "id" => 1
        })

      conn = conn(:post, "/mcp", body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> MCPPlug.call(@opts)

      assert conn.status == 406
    end

    test "uses provided session ID" do
      session_id = "test_session_123"

      body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "initialize",
          "params" => %{},
          "id" => 1
        })

      conn = conn(:post, "/mcp", body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)
        |> MCPPlug.call(@opts)

      assert conn.status == 200
      assert get_resp_header(conn, "mcp-session-id") == [session_id]
    end

    test "handles full workflow" do
      # Initialize
      init_body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "initialize",
          "params" => %{},
          "id" => 1
        })

      conn = conn(:post, "/mcp", init_body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> MCPPlug.call(@opts)

      [session_id] = get_resp_header(conn, "mcp-session-id")

      # Call tool
      call_body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "params" => %{
            "name" => "greet",
            "arguments" => %{"name" => "MCP"}
          },
          "id" => 2
        })

      conn = conn(:post, "/mcp", call_body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)
        |> MCPPlug.call(@opts)

      assert conn.status == 200
      response = JSON.decode!(conn.resp_body)
      [content] = response["result"]["content"]
      assert content["text"] == "Hello, MCP!"
    end
  end

  describe "DELETE /mcp" do
    test "deletes session" do
      session_id = SimpleMCP.Session.generate_id()
      SimpleMCP.Session.create(session_id)

      conn =
        :delete
        |> conn("/mcp")
        |> put_req_header("mcp-session-id", session_id)
        |> MCPPlug.call(@opts)

      assert conn.status == 204
      assert SimpleMCP.Session.get(session_id) == nil
    end

    test "returns error without session ID" do
      conn = MCPPlug.call(conn(:delete, "/mcp"), @opts)

      assert conn.status == 400
    end
  end
end
