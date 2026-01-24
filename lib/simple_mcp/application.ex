defmodule SimpleMCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS table
    SimpleMCP.Session.init()

    children = [
      # Session cleanup task
      {Task, fn -> cleanup_loop() end}
    ]

    opts = [strategy: :one_for_one, name: SimpleMCP.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cleanup_loop do
    Process.sleep(SimpleMCP.Session.cleanup_interval())
    SimpleMCP.Session.cleanup_expired()
    cleanup_loop()
  end
end
