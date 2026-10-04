defmodule SimpleMCP.ContextServer do
  @moduledoc """
  A server that defines the three-argument `handle_tool_call/3`, so a tool can see
  who is calling (slice 318). It echoes the context it received as text.
  """

  use SimpleMCP

  @impl true
  def server_info, do: {"Context Server", "1.0.0"}

  @impl true
  def tools do
    [SimpleMCP.Tool.new("whoami", "Reports the caller", %{})]
  end

  @impl true
  def handle_tool_call("whoami", _arguments, context) do
    {:ok, "caller=#{inspect(context)}"}
  end
end
