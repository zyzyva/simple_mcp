defmodule SimpleMCP.StructuredContentTest do
  @moduledoc """
  Slice 318 behaviour 5: a tool answers with its own content list, passed through
  unchanged, so a host can return a text block and a link together. The marker is the
  tagged `{:content, blocks}` return, so a plain map that happens to have a `content`
  key still encodes exactly as it did before.
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.Plug, as: MCPPlug
  alias SimpleMCP.Protocol
  alias SimpleMCP.StructuredServer

  @blocks [
    %{"type" => "text", "text" => "Your receipt is saved."},
    %{"type" => "resource_link", "uri" => "https://example.com/r/7", "name" => "Open receipt"}
  ]

  describe "a tool that returns {:content, blocks}" do
    test "passes the blocks through unchanged" do
      message = call("share")

      response = Protocol.handle_message(message, StructuredServer, nil, stateless: true)

      assert response["result"] == %{"content" => @blocks}
    end

    test "passes the blocks through unchanged over the plug" do
      opts = MCPPlug.init(server: StructuredServer, stateless: true)

      conn =
        :post
        |> Plug.Test.conn("/mcp", JSON.encode!(Map.put(call("share"), :jsonrpc, "2.0")))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
        |> MCPPlug.call(opts)

      assert %{"result" => %{"content" => @blocks}} = JSON.decode!(conn.resp_body)
    end
  end

  describe "the existing return shapes" do
    test "a plain map with a content key is still encoded as JSON text" do
      message = call("plain_map")

      response = Protocol.handle_message(message, StructuredServer, nil, stateless: true)

      assert response["result"] == %{
               "content" => [
                 %{"type" => "text", "text" => JSON.encode!(%{"content" => @blocks})}
               ]
             }
    end

    test "a binary is still a text block" do
      response = Protocol.handle_message(call("text"), StructuredServer, nil, stateless: true)

      assert response["result"] == %{"content" => [%{"type" => "text", "text" => "plain"}]}
    end
  end

  defp call(name) do
    %{id: 1, method: "tools/call", params: %{"name" => name, "arguments" => %{}}}
  end
end
