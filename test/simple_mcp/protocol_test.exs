defmodule SimpleMCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias SimpleMCP.{Protocol, Session}

  setup do
    session_id = Session.generate_id()
    Session.create(session_id)
    %{session_id: session_id}
  end

  describe "parse_request/1" do
    test "parses valid JSON-RPC 2.0 request" do
      body = ~s({"jsonrpc": "2.0", "method": "test", "params": {"foo": "bar"}, "id": 1})
      assert {:ok, message} = Protocol.parse_request(body)
      assert message.method == "test"
      assert message.params == %{"foo" => "bar"}
      assert message.id == 1
    end

    test "returns error for invalid JSON" do
      assert {:error, -32_700, "Parse error"} = Protocol.parse_request("not json")
    end

    test "returns error for missing jsonrpc field" do
      body = ~s({"method": "test", "id": 1})
      assert {:error, -32_600, _} = Protocol.parse_request(body)
    end
  end

  describe "handle_message/3 - initialize" do
    test "handles initialize request", %{session_id: session_id} do
      message = %{
        id: 1,
        method: "initialize",
        params: %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "test", "version" => "1.0"}
        }
      }

      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["serverInfo"]["name"] == "Test Server"
      assert response["result"]["capabilities"]["tools"] == %{}
    end
  end

  describe "handle_message/3 - tools/list" do
    test "lists tools after initialization", %{session_id: session_id} do
      # First initialize
      init_msg = %{id: 1, method: "initialize", params: %{}}
      Protocol.handle_message(init_msg, SimpleMCP.TestServer, session_id)

      # Then list tools
      message = %{id: 2, method: "tools/list", params: %{}}
      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      assert response["result"]["tools"]
      tools = response["result"]["tools"]
      assert length(tools) == 3
      assert Enum.any?(tools, fn t -> t["name"] == "greet" end)
    end

    test "returns error when not initialized" do
      new_session_id = "uninitialized_session"
      message = %{id: 1, method: "tools/list", params: %{}}
      response = Protocol.handle_message(message, SimpleMCP.TestServer, new_session_id)

      assert response["error"]
      assert response["error"]["message"] == "Server not initialized"
    end
  end

  describe "handle_message/3 - tools/call" do
    setup %{session_id: session_id} do
      init_msg = %{id: 1, method: "initialize", params: %{}}
      Protocol.handle_message(init_msg, SimpleMCP.TestServer, session_id)
      :ok
    end

    test "calls greet tool", %{session_id: session_id} do
      message = %{
        id: 2,
        method: "tools/call",
        params: %{"name" => "greet", "arguments" => %{"name" => "World"}}
      }

      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      assert response["result"]["content"]
      [content] = response["result"]["content"]
      assert content["text"] == "Hello, World!"
    end

    test "calls add tool", %{session_id: session_id} do
      message = %{
        id: 2,
        method: "tools/call",
        params: %{"name" => "add", "arguments" => %{"a" => 5, "b" => 3}}
      }

      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      [content] = response["result"]["content"]
      assert content["text"] =~ "8"
    end

    test "handles tool errors", %{session_id: session_id} do
      message = %{
        id: 2,
        method: "tools/call",
        params: %{"name" => "unknown_tool", "arguments" => %{}}
      }

      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      assert response["result"]["isError"] == true
    end
  end

  describe "handle_message/3 - ping" do
    test "handles ping", %{session_id: session_id} do
      message = %{id: 1, method: "ping", params: %{}}
      response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)

      assert response["result"] == %{}
    end
  end
end
