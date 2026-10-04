defmodule SimpleMCP.StructuredServer do
  @moduledoc """
  A server whose tools return the three shapes slice 318 cares about: the tagged
  `{:content, blocks}` pass-through, a plain map with a `content` key (which must
  still encode as JSON text), and a binary.
  """

  use SimpleMCP

  @blocks [
    %{"type" => "text", "text" => "Your receipt is saved."},
    %{"type" => "resource_link", "uri" => "https://example.com/r/7", "name" => "Open receipt"}
  ]

  @impl true
  def handle_tool_call("share", _args), do: {:ok, {:content, @blocks}}
  def handle_tool_call("plain_map", _args), do: {:ok, %{"content" => @blocks}}
  def handle_tool_call("text", _args), do: {:ok, "plain"}
end
