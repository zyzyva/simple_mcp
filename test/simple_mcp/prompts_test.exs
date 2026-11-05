defmodule SimpleMCP.PromptsTest do
  @moduledoc """
  Slice 424 behaviour 2: a server that defines the optional `prompts/0` and `get_prompt/3` callbacks
  advertises the `prompts` capability and answers `prompts/list` and `prompts/get` (MCP 2025-06-18). A
  server that does not is pinned byte for byte by `SimpleMCP.CompatMasterTest`.

  A missing required argument, an unknown prompt and any rendering failure are proper JSON-RPC errors
  (-32602 invalid params, -32603 internal error), never a crash and never an HTTP 500.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias SimpleMCP.Plug, as: MCPPlug
  alias SimpleMCP.Protocol

  @accept "application/json, text/event-stream"
  @invalid_params -32_602
  @internal_error -32_603

  defp call(method, params, opts \\ [], server \\ SimpleMCP.PromptsServer) do
    message = %{id: 7, method: method, params: params}
    Protocol.handle_message(message, server, nil, Keyword.put_new(opts, :stateless, true))
  end

  defp get(name, arguments \\ nil, opts \\ []) do
    params =
      if arguments, do: %{"name" => name, "arguments" => arguments}, else: %{"name" => name}

    call("prompts/get", params, opts)
  end

  defp error_of(response), do: response["error"]

  describe "the capability" do
    test "a server with prompts advertises prompts next to tools, with no listChanged" do
      result = call("initialize", %{})["result"]

      assert result["capabilities"] == %{"tools" => %{}, "prompts" => %{}}
    end

    test "instructions and prompts together" do
      result = call("initialize", %{})["result"]

      assert result["instructions"] == "Be brief."
      assert Map.has_key?(result["capabilities"], "prompts")
    end

    test "a server with no prompts advertises none, and answers method-not-found for both methods" do
      result = call("initialize", %{}, [], SimpleMCP.CompatServer)["result"]
      assert result["capabilities"] == %{"tools" => %{}}

      for method <- ["prompts/list", "prompts/get"] do
        response = call(method, %{"name" => "x"}, [], SimpleMCP.CompatServer)

        assert response["error"] == %{
                 "code" => -32_601,
                 "message" => "Method not found: #{method}"
               }
      end
    end
  end

  describe "prompts/list" do
    test "returns every prompt in the order defined, in the MCP shape" do
      %{"result" => %{"prompts" => prompts}} = call("prompts/list", %{})

      assert hd(prompts) == %{
               "name" => "review",
               "title" => "Review my receipts",
               "description" => "Asks the assistant to look over flagged receipts",
               "arguments" => [
                 %{"name" => "topic", "description" => "What to review", "required" => true},
                 %{"name" => "tone", "description" => "How to say it", "required" => false},
                 %{"name" => "focus", "required" => true}
               ]
             }

      assert Enum.at(prompts, 1) == %{"name" => "plain"}
      assert length(prompts) == length(SimpleMCP.PromptsServer.prompts())
    end

    test "has no nextCursor: the whole list, and a cursor from the client changes nothing" do
      whole = call("prompts/list", %{})
      with_cursor = call("prompts/list", %{"cursor" => "anything"})

      assert whole == with_cursor
      refute Map.has_key?(whole["result"], "nextCursor")
    end

    test "echoes the request id and is a plain JSON-RPC success" do
      assert %{"jsonrpc" => "2.0", "id" => 7, "result" => %{"prompts" => _}} =
               call("prompts/list", %{})
    end

    test "a prompts/0 that raises is a JSON-RPC internal error, logged, with nothing leaked" do
      log =
        capture_log(fn ->
          send(self(), {:r, call("prompts/list", %{}, [], SimpleMCP.RaisingPromptsServer)})
        end)

      assert_received {:r, response}
      assert %{"code" => @internal_error, "message" => message} = error_of(response)
      refute message =~ "blew up"
      assert log =~ "prompts blew up"
    end
  end

  describe "prompts/get: rendering" do
    test "returns the rendered messages, string content as a text block" do
      response = get("review", %{"topic" => "receipts", "tone" => "kindly", "focus" => "totals"})

      assert response["result"] == %{
               "messages" => [
                 %{
                   "role" => "user",
                   "content" => %{"type" => "text", "text" => "Please review receipts, kindly."}
                 }
               ]
             }
    end

    test "content blocks (text, image, resource) pass through, roles become strings, description is carried" do
      assert %{"result" => result} = get("rich")

      assert result["description"] == "A rich prompt"

      assert [
               %{"role" => "user", "content" => %{"type" => "text", "text" => "Look at this"}},
               %{
                 "role" => "assistant",
                 "content" => %{"type" => "image", "mimeType" => "image/png"}
               },
               %{
                 "role" => "user",
                 "content" => %{"type" => "resource", "resource" => %{"uri" => "resource://x"}}
               }
             ] = result["messages"]
    end

    test "no description unless the server gives one" do
      refute Map.has_key?(get("plain")["result"], "description")
    end

    test "messages written with string keys work too" do
      assert [%{"role" => "user", "content" => %{"text" => "string keys work"}}] =
               get("string_keys")["result"]["messages"]
    end

    test "all the arguments the client sent reach the server, absent ones as an empty map" do
      assert [%{"content" => %{"text" => text}}] =
               get("echo_args", %{"a" => "1", "extra" => "2"})["result"]["messages"]

      assert text == ~s(args=%{"a" => "1", "extra" => "2"})

      assert [%{"content" => %{"text" => "args=%{}"}}] = get("echo_args")["result"]["messages"]

      assert [%{"content" => %{"text" => "args=%{}"}}] =
               call("prompts/get", %{"name" => "echo_args", "arguments" => nil})["result"][
                 "messages"
               ]
    end

    test "a prompt with no arguments renders with none" do
      assert get("plain")["result"]["messages"] != []
    end
  end

  describe "prompts/get: the caller's context (the same as handle_tool_call/3 receives)" do
    test "Protocol.handle_message hands the context option to get_prompt/3" do
      response = get("whoami", nil, context: %{id: 7})

      assert [%{"content" => %{"text" => "caller=%{id: 7}"}}] = response["result"]["messages"]
    end

    test "no context is nil" do
      assert [%{"content" => %{"text" => "caller=nil"}}] = get("whoami")["result"]["messages"]
    end

    test "over HTTP the host's assign reaches get_prompt/3, in stateless and session modes" do
      for opts <- [[], [stateless: true]] do
        conn =
          "whoami"
          |> post_get()
          |> assign(:simple_mcp_context, :caller_from_plug)
          |> MCPPlug.call(MCPPlug.init([server: SimpleMCP.PromptsServer] ++ opts))

        assert conn.status == 200

        assert %{
                 "result" => %{
                   "messages" => [%{"content" => %{"text" => "caller=:caller_from_plug"}}]
                 }
               } =
                 JSON.decode!(conn.resp_body)
      end
    end
  end

  describe "prompts/get: errors are JSON-RPC errors, never a crash" do
    test "an unknown prompt is invalid params and names it" do
      assert %{"code" => @invalid_params, "message" => "Unknown prompt: nope"} =
               error_of(get("nope"))
    end

    test "a missing prompt name, a null one, and a name that is not a string" do
      for params <- [%{}, %{"name" => nil}, %{"name" => 5}, %{"name" => ["review"]}] do
        assert %{"code" => @invalid_params, "message" => message} =
                 error_of(call("prompts/get", params))

        assert message =~ "name"
      end
    end

    test "params that are not an object" do
      assert %{"code" => @invalid_params} = error_of(call("prompts/get", nil))
      assert %{"code" => @invalid_params} = error_of(call("prompts/get", ["review"]))
    end

    test "a missing required argument is invalid params and names it, and the server is not called" do
      assert %{"code" => @invalid_params, "message" => message} = error_of(get("review", %{}))
      assert message == "Missing required argument(s): topic, focus"

      assert %{"message" => "Missing required argument(s): focus"} =
               error_of(get("review", %{"topic" => "x"}))
    end

    test "a required argument sent as null counts as missing" do
      assert %{"code" => @invalid_params} =
               error_of(get("review", %{"topic" => nil, "focus" => "x"}))
    end

    test "arguments that are not an object" do
      for arguments <- ["topic=x", ["x"], 3] do
        assert %{"code" => @invalid_params, "message" => message} =
                 error_of(call("prompts/get", %{"name" => "plain", "arguments" => arguments}))

        assert message =~ "arguments"
      end
    end

    test "{:error, text} from the server is an internal error carrying that text" do
      assert %{"code" => @internal_error, "message" => "No receipts to review"} =
               error_of(get("error_text"))
    end

    test "{:error, term} is an internal error with the term shown" do
      assert %{"code" => @internal_error, "message" => message} = error_of(get("error_term"))
      assert message =~ "not_ready"
    end

    test "a raise is an internal error, logged, and the exception text never reaches the client" do
      log =
        capture_log(fn ->
          send(self(), {:r, get("boom")})
        end)

      assert_received {:r, response}
      assert %{"code" => @internal_error, "message" => message} = error_of(response)
      assert message == "Internal error rendering prompt"
      refute inspect(response) =~ "secret internal detail"
      assert log =~ "secret internal detail"
    end

    test "an exit and a throw are internal errors too" do
      for name <- ["exits", "throws"] do
        log = capture_log(fn -> send(self(), {:r, get(name)}) end)
        assert_received {:r, response}

        assert %{"code" => @internal_error, "message" => "Internal error rendering prompt"} =
                 error_of(response)

        assert log =~ "prompt"
      end
    end

    test "a result that is not {:ok, _} or {:error, _}, a bad role, bad content, and a non-list of messages" do
      for name <- ["bad_result", "bad_role", "bad_content", "bad_messages"] do
        assert %{"code" => @internal_error, "message" => "Invalid prompt result"} =
                 error_of(get(name))
      end
    end

    test "a server that lists prompts but defines no get_prompt/3 answers an internal error" do
      response = call("prompts/get", %{"name" => "lonely"}, [], SimpleMCP.ListOnlyPromptsServer)

      assert %{"code" => @internal_error, "message" => message} = error_of(response)
      assert message =~ "get_prompt/3"
    end

    test "an HTTP request for any of these is still a 200 JSON-RPC response, never a 500" do
      for name <- ["boom", "nope", "bad_result", "error_text"] do
        capture_log(fn ->
          conn = MCPPlug.call(post_get(name), MCPPlug.init(server: SimpleMCP.PromptsServer))
          send(self(), {:conn, conn})
        end)

        assert_received {:conn, conn}
        assert conn.status == 200
        assert %{"error" => %{"code" => code}} = JSON.decode!(conn.resp_body)
        assert code in [@invalid_params, @internal_error]
      end
    end
  end

  describe "the README's examples" do
    test "work as the README says" do
      server = SimpleMCP.ReadmeServer

      init =
        Protocol.handle_message(%{id: 1, method: "initialize", params: %{}}, server, nil,
          stateless: true
        )

      assert init["result"]["instructions"] =~ "Ask the person before changing anything"
      assert init["result"]["capabilities"]["prompts"] == %{}

      list = call("prompts/list", %{}, [], server)

      assert [
               %{
                 "name" => "review_flagged",
                 "arguments" => [%{"name" => "month", "required" => false}]
               }
             ] =
               list["result"]["prompts"]

      rendered =
        call(
          "prompts/get",
          %{"name" => "review_flagged", "arguments" => %{"month" => "2026-09"}},
          [context: %{email: "a@example.com"}],
          server
        )

      assert [
               %{
                 "content" => %{"text" => "Review a@example.com's flagged receipts from 2026-09."}
               }
             ] =
               rendered["result"]["messages"]
    end
  end

  describe "sessions, the same rule as tools/list" do
    test "in the default mode an unknown session is 'Server not initialized' for both methods" do
      for {method, params} <- [{"prompts/list", %{}}, {"prompts/get", %{"name" => "plain"}}] do
        message = %{id: 1, method: method, params: params}

        response =
          Protocol.handle_message(message, SimpleMCP.PromptsServer, "no-such-session-424")

        assert %{"code" => -32_600, "message" => "Server not initialized"} = response["error"]
      end
    end

    test "stateless mode needs no session at all" do
      assert %{"result" => %{"prompts" => _}} = call("prompts/list", %{})
      assert %{"result" => %{"messages" => _}} = get("plain")
    end

    test "over HTTP in the default mode, a client-supplied session works like tools/list" do
      conn =
        MCPPlug.call(post_rpc("prompts/list", %{}), MCPPlug.init(server: SimpleMCP.PromptsServer))

      assert conn.status == 200
      assert %{"result" => %{"prompts" => [_ | _]}} = JSON.decode!(conn.resp_body)
      assert get_resp_header(conn, "mcp-session-id") != []
    end
  end

  defp post_get(name, arguments \\ %{}) do
    post_rpc("prompts/get", %{"name" => name, "arguments" => arguments})
  end

  defp post_rpc(method, params) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "id" => 3, "method" => method, "params" => params})

    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", @accept)
  end
end
