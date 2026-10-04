defmodule SimpleMCP.CallerContextTest do
  @moduledoc """
  Slice 318 behaviour 2: a tool receives the caller the host app put on the connection
  under `:simple_mcp_context`. A two-argument server is unaffected.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.{Plug, Protocol, Session}

  @accept "application/json, text/event-stream"

  describe "three-argument server" do
    test "receives exactly the assign value the host put on the connection" do
      opts = Plug.init(server: SimpleMCP.ContextServer, stateless: true)

      conn =
        "whoami"
        |> post_call(%{})
        |> assign(:simple_mcp_context, %{id: 7})
        |> Plug.call(opts)

      assert text_of(conn) == "caller=%{id: 7}"
    end

    test "receives nil when the host put nothing on the connection" do
      opts = Plug.init(server: SimpleMCP.ContextServer, stateless: true)

      conn = Plug.call(post_call("whoami", %{}), opts)

      assert text_of(conn) == "caller=nil"
    end

    test "works on the stateful path too, after an initialize" do
      opts = Plug.init(server: SimpleMCP.ContextServer)
      session_id = Session.generate_id()

      init = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}

      init_conn =
        :post
        |> conn("/mcp", JSON.encode!(init))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", @accept)
        |> put_req_header("mcp-session-id", session_id)
        |> Plug.call(opts)

      assert init_conn.status == 200

      conn =
        "whoami"
        |> post_call(%{}, session_id)
        |> assign(:simple_mcp_context, :caller_one)
        |> Plug.call(opts)

      assert text_of(conn) == "caller=:caller_one"
    end
  end

  describe "two-argument server" do
    test "is called exactly as before, with the assign present" do
      opts = Plug.init(server: SimpleMCP.CompatServer, stateless: true)

      conn =
        "greet"
        |> post_call(%{"name" => "Ana"})
        |> assign(:simple_mcp_context, %{id: 7})
        |> Plug.call(opts)

      assert text_of(conn) == "Hello, Ana!"
    end
  end

  describe "Protocol.handle_message/4" do
    test "hands the context option to a three-argument server" do
      message = %{id: 3, method: "tools/call", params: %{"name" => "whoami", "arguments" => %{}}}

      response =
        Protocol.handle_message(message, SimpleMCP.ContextServer, nil,
          stateless: true,
          context: :from_test
        )

      assert [%{"text" => "caller=:from_test"}] = response["result"]["content"]
    end
  end

  defp post_call(tool, arguments, session_id \\ nil) do
    body =
      JSON.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => tool, "arguments" => arguments}
      })

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
    |> put_session(session_id)
  end

  defp put_session(conn, nil), do: conn
  defp put_session(conn, session_id), do: put_req_header(conn, "mcp-session-id", session_id)

  defp text_of(conn) do
    %{"result" => %{"content" => [%{"text" => text}]}} = JSON.decode!(conn.resp_body)
    text
  end
end
