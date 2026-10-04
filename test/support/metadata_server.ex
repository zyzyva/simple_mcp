defmodule SimpleMCP.MetadataServer do
  @moduledoc """
  A server whose first tool sets a title and a read-only hint, and whose second tool
  sets neither (slice 318). Lives in test/support so it compiles before the tests run.
  """

  use SimpleMCP

  @impl true
  def tools do
    [
      SimpleMCP.Tool.new("lookup", "Looks up", %{},
        title: "Look up a receipt",
        annotations: [read_only: true]
      ),
      SimpleMCP.Tool.new("plain", "Plain", %{})
    ]
  end
end
