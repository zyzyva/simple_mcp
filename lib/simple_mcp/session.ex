defmodule SimpleMCP.Session do
  @moduledoc """
  Simple ETS-based session management for MCP connections.
  Sessions auto-expire after 30 minutes of inactivity.
  """

  @table :simple_mcp_sessions
  @ttl_ms 30 * 60 * 1000  # 30 minutes
  @cleanup_interval 60_000  # Check every minute

  @doc """
  Initializes the ETS table. Called by Application.
  """
  def init do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc """
  Gets or creates a session.
  """
  def get_or_create(session_id) do
    case get(session_id) do
      nil -> create(session_id)
      session -> session
    end
  end

  @doc """
  Gets a session by ID.
  """
  def get(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session, _expires_at}] -> session
      [] -> nil
    end
  end

  @doc """
  Creates a new session.
  """
  def create(session_id) do
    session = %{
      initialized: false,
      protocol_version: nil,
      client_info: nil,
      created_at: System.system_time(:millisecond)
    }

    expires_at = System.system_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {session_id, session, expires_at})
    session
  end

  @doc """
  Updates a session with new data.
  """
  def update(session_id, attrs) do
    case get(session_id) do
      nil ->
        session = Map.merge(create(session_id), attrs)
        expires_at = System.system_time(:millisecond) + @ttl_ms
        :ets.insert(@table, {session_id, session, expires_at})
        session

      session ->
        updated = Map.merge(session, attrs)
        expires_at = System.system_time(:millisecond) + @ttl_ms
        :ets.insert(@table, {session_id, updated, expires_at})
        updated
    end
  end

  @doc """
  Deletes a session.
  """
  def delete(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  @doc """
  Generates a new unique session ID.
  """
  def generate_id do
    "session_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  @doc """
  Removes expired sessions. Called periodically.
  """
  def cleanup_expired do
    now = System.system_time(:millisecond)

    :ets.foldl(
      fn {session_id, _session, expires_at}, acc ->
        if expires_at < now do
          :ets.delete(@table, session_id)
        end
        acc
      end,
      :ok,
      @table
    )
  end

  @doc """
  Returns the cleanup interval in milliseconds.
  """
  def cleanup_interval, do: @cleanup_interval
end
