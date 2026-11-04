defmodule SimpleMCP.InstructionsTest do
  @moduledoc """
  Slice 424 behaviour 1: a server that defines the optional `instructions/0` callback has its string
  carried in the `initialize` result as `instructions` (MCP 2025-06-18, `InitializeResult.instructions`);
  a server that does not has no `instructions` key at all.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.Plug, as: MCPPlug
  alias SimpleMCP.Protocol

  @accept "application/json, text/event-stream"
  @text "Always ask the person before changing anything.\nPrefer short answers. Naïve café ✓"

  defp initialize(server, params \\ %{}) do
    message = %{id: 1, method: "initialize", params: params}
    Protocol.handle_message(message, server, nil, stateless: true)["result"]
  end

  describe "a server that defines instructions/0" do
    test "the initialize result carries the string, unchanged, as instructions" do
      assert %{"instructions" => @text} = initialize(SimpleMCP.InstructionsServer)
    end

    test "everything else in the result is as it was: version, server info, the tools capability only" do
      result = initialize(SimpleMCP.InstructionsServer, %{"protocolVersion" => "2025-06-18"})

      assert Map.delete(result, "instructions") == %{
               "protocolVersion" => "2025-06-18",
               "serverInfo" => %{"name" => "Instructions Server", "version" => "1.0.0"},
               "capabilities" => %{"tools" => %{}}
             }
    end

    test "over HTTP, in the default session mode and in stateless mode, the bytes carry it" do
      for opts <- [
            [server: SimpleMCP.InstructionsServer],
            [server: SimpleMCP.InstructionsServer, stateless: true]
          ] do
        conn = MCPPlug.call(post_initialize(), MCPPlug.init(opts))

        assert conn.status == 200
        assert %{"result" => %{"instructions" => @text}} = JSON.decode!(conn.resp_body)
      end
    end

    test "it is read on every initialize, not captured once" do
      first = initialize(SimpleMCP.InstructionsServer)["instructions"]
      second = initialize(SimpleMCP.InstructionsServer)["instructions"]

      assert first == second
      assert first == @text
    end
  end

  describe "a server that does not" do
    test "has no instructions key at all, not null and not an empty string" do
      result = initialize(SimpleMCP.CompatServer)

      refute Map.has_key?(result, "instructions")
      assert Enum.sort(Map.keys(result)) == ["capabilities", "protocolVersion", "serverInfo"]
    end

    test "defines no instructions/0 (the default is not a function the library adds)" do
      refute function_exported?(SimpleMCP.CompatServer, :instructions, 0)
      assert function_exported?(SimpleMCP.InstructionsServer, :instructions, 0)
    end
  end

  describe "a server whose instructions/0 has nothing usable" do
    test "nil leaves the key out" do
      refute Map.has_key?(initialize(SimpleMCP.NilInstructionsServer), "instructions")
    end

    test "something that is not a string leaves the key out, logs it, and the handshake still works" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          send(self(), {:result, initialize(SimpleMCP.BadInstructionsServer)})
        end)

      assert_received {:result, result}
      assert log =~ "SimpleMCP.BadInstructionsServer.instructions/0 must return a string or nil"

      refute Map.has_key?(result, "instructions")
      assert result["serverInfo"]["name"] == "SimpleMCP Server"
      assert result["capabilities"] == %{"tools" => %{}}
    end
  end

  defp post_initialize do
    body =
      JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
  end
end
