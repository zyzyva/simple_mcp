defmodule SimpleMCP.Plug do
  @moduledoc """
  A Plug endpoint for handling MCP requests over HTTP.

  ## Usage

  In your Phoenix router:

      forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer

  Or in a Plug router:

      forward "/mcp", to: SimpleMCP.Plug, init_opts: [server: MyApp.MCPServer]
  """

  @behaviour Plug

  import Plug.Conn
  alias SimpleMCP.{Protocol, Session}

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :server)
    %{server: server}
  end

  @impl true
  def call(conn, %{server: server}) do
    case conn.method do
      "POST" -> handle_post(conn, server)
      "DELETE" -> handle_delete(conn)
      _ -> send_error(conn, 405, "Method not allowed")
    end
  end

  defp handle_post(conn, server) do
    # Check required headers
    if accepts_json_and_sse?(conn) do
      session_id = get_or_create_session_id(conn)

      # Get body - either from already-parsed body_params or read raw body
      {body, conn} = get_request_body(conn)

      case Protocol.parse_request(body) do
        {:ok, message} ->
          handle_message(conn, message, server, session_id)

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

  defp handle_message(conn, message, server, session_id) do
    case Protocol.handle_message(message, server, session_id) do
      :no_response ->
        # For notifications, return 202 Accepted
        conn
        |> put_resp_header("mcp-session-id", session_id)
        |> send_resp(202, "")

      response ->
        conn
        |> put_resp_header("mcp-session-id", session_id)
        |> put_resp_content_type("application/json")
        |> send_resp(200, JSON.encode!(response))
    end
  end

  defp handle_delete(conn) do
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
