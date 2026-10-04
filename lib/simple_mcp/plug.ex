defmodule SimpleMCP.Plug do
  @moduledoc """
  A Plug endpoint for handling MCP requests over HTTP.

  ## Usage

  In your Phoenix router:

      forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer

  Or in a Plug router:

      forward "/mcp", to: SimpleMCP.Plug, init_opts: [server: MyApp.MCPServer]

  ## Options (all off by default; with none set, responses are unchanged)

    * `:server` - required, the module implementing `SimpleMCP`.
    * `:stateless` - when `true`, the server never creates, stores, requires or
      returns an `Mcp-Session-Id`. `initialize`, `tools/list` and `tools/call` each
      work on their own, on any machine. GET and DELETE answer 405. A client that
      sends a session header anyway is served and the header is ignored.

          forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer, stateless: true

  ## Caller context

  Before the plug runs, the host app can put the caller on the connection under the
  assign key `:simple_mcp_context`. A server that defines
  `handle_tool_call/3` (tool name, arguments, context) receives that value. A server
  that only defines `handle_tool_call/2` is called exactly as before.

      plug :put_mcp_caller

      def put_mcp_caller(conn, _opts) do
        assign(conn, :simple_mcp_context, conn.assigns.current_user)
      end
  """

  @behaviour Plug

  import Plug.Conn
  alias SimpleMCP.{Protocol, Session}

  @context_assign :simple_mcp_context

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :server)
    %{server: server, stateless: Keyword.get(opts, :stateless, false)}
  end

  @impl true
  def call(conn, config) do
    case conn.method do
      "POST" -> handle_post(conn, config)
      "DELETE" -> handle_delete(conn, config)
      _ -> send_error(conn, 405, "Method not allowed")
    end
  end

  defp handle_post(conn, config) do
    # Check required headers
    if accepts_json_and_sse?(conn) do
      session_id = session_for(conn, config)

      # Get body - either from already-parsed body_params or read raw body
      {body, conn} = get_request_body(conn)

      case Protocol.parse_request(body) do
        {:ok, message} ->
          handle_message(conn, message, config, session_id)

        {:error, code, reason} ->
          send_json_rpc_error(conn, nil, code, reason)
      end
    else
      send_json_rpc_error(
        conn,
        nil,
        -32_600,
        "Not Acceptable: Client must accept both application/json and text/event-stream",
        406
      )
    end
  end

  defp get_request_body(conn) do
    cond do
      # Body not yet fetched - read raw body
      match?(%Plug.Conn.Unfetched{}, conn.body_params) ->
        {:ok, body, conn} = read_body(conn)
        {body, conn}

      # Body was parsed as JSON by Plug.Parsers - use body_params directly.
      # Once past the Unfetched? check above, Plug.Conn.t()'s own spec
      # guarantees body_params is a map, so no separate is_map/1 guard is
      # reachable-false here (Dialyzer flagged the redundant check).
      map_size(conn.body_params) > 0 ->
        {conn.body_params, conn}

      # Fallback - try to read raw body
      true ->
        case read_body(conn) do
          {:ok, body, conn} when byte_size(body) > 0 -> {body, conn}
          _ -> {conn.body_params, conn}
        end
    end
  end

  defp session_for(_conn, %{stateless: true}), do: nil
  defp session_for(conn, _config), do: get_or_create_session_id(conn)

  defp handle_message(conn, message, %{server: server, stateless: true}, nil) do
    response =
      Protocol.handle_message(message, server, nil, stateless: true, context: caller(conn))

    send_message_response(conn, response)
  end

  defp handle_message(conn, message, %{server: server}, session_id) do
    response = Protocol.handle_message(message, server, session_id, context: caller(conn))

    conn
    |> put_resp_header("mcp-session-id", session_id)
    |> send_message_response(response)
  end

  defp send_message_response(conn, :no_response) do
    # For notifications, return 202 Accepted
    send_resp(conn, 202, "")
  end

  defp send_message_response(conn, response) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(response))
  end

  defp caller(conn), do: Map.get(conn.assigns, @context_assign)

  defp handle_delete(conn, %{stateless: true}), do: send_error(conn, 405, "Method not allowed")

  defp handle_delete(conn, _config) do
    case get_session_id(conn) do
      nil ->
        send_error(conn, 400, "Missing session ID")

      session_id ->
        Session.delete(session_id)
        send_resp(conn, 204, "")
    end
  end

  defp get_or_create_session_id(conn) do
    case get_session_id(conn) do
      nil ->
        session_id = Session.generate_id()
        Session.create(session_id)
        session_id

      session_id ->
        Session.get_or_create(session_id)
        session_id
    end
  end

  defp get_session_id(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [session_id | _] -> session_id
      [] -> nil
    end
  end

  defp accepts_json_and_sse?(conn) do
    accept = List.first(get_req_header(conn, "accept")) || ""
    String.contains?(accept, "application/json") and String.contains?(accept, "text/event-stream")
  end

  defp send_json_rpc_error(conn, id, code, message, http_status \\ 200) do
    response = Protocol.error_response(id, code, message, %{"message" => message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(http_status, JSON.encode!(response))
  end

  defp send_error(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
