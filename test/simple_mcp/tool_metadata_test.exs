defmodule SimpleMCP.ToolMetadataTest do
  @moduledoc """
  Slice 318 behaviour 3: a tool may carry a title and the four MCP hints. They appear
  in `tools/list` under the MCP field names when set, and not at all when not set.
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.{Protocol, Session, Tool}

  describe "a tool with a title and annotations" do
    test "emits title and every hint under the MCP field names" do
      tool =
        Tool.new("lookup", "Looks up a receipt", %{},
          title: "Look up a receipt",
          annotations: [read_only: true, destructive: false, idempotent: true, open_world: false]
        )

      assert %{
               "name" => "lookup",
               "title" => "Look up a receipt",
               "annotations" => %{
                 "readOnlyHint" => true,
                 "destructiveHint" => false,
                 "idempotentHint" => true,
                 "openWorldHint" => false
               }
             } = Tool.to_mcp_format(tool)
    end

    test "accepts annotations as a map" do
      tool = Tool.new("lookup", "Looks up", %{}, annotations: %{read_only: true})

      assert Tool.to_mcp_format(tool)["annotations"] == %{"readOnlyHint" => true}
    end

    test "emits only the hints that were given" do
      tool = Tool.new("lookup", "Looks up", %{}, annotations: [destructive: true])

      assert Tool.to_mcp_format(tool)["annotations"] == %{"destructiveHint" => true}
    end

    test "a title alone emits no annotations key" do
      tool = Tool.new("lookup", "Looks up", %{}, title: "Look up")

      assert Tool.to_mcp_format(tool)["title"] == "Look up"
      refute Map.has_key?(Tool.to_mcp_format(tool), "annotations")
    end
  end

  describe "a tool without them" do
    test "is emitted exactly as before: no title and no annotations keys, not even empty" do
      formatted = Tool.to_mcp_format(Tool.new("plain", "A plain tool", %{}))

      assert Enum.sort(Map.keys(formatted)) == ["description", "inputSchema", "name"]
    end

    test "empty annotations are treated as not set" do
      formatted = Tool.to_mcp_format(Tool.new("plain", "A plain tool", %{}, annotations: []))

      refute Map.has_key?(formatted, "annotations")
    end
  end

  describe "bad annotations" do
    test "an unknown hint raises" do
      assert_raise ArgumentError, ~r/unknown annotation :read_onyl/, fn ->
        Tool.new("typo", "Typo", %{}, annotations: [read_onyl: true])
      end
    end

    test "a non-boolean hint raises" do
      assert_raise ArgumentError, ~r/must be a boolean/, fn ->
        Tool.new("typo", "Typo", %{}, annotations: [read_only: "yes"])
      end
    end
  end

  describe "tools/list" do
    test "carries the title and annotations for a server that sets them" do
      session_id = Session.generate_id()

      Protocol.handle_message(
        %{id: 1, method: "initialize", params: %{}},
        MetadataServer,
        session_id
      )

      response =
        Protocol.handle_message(
          %{id: 2, method: "tools/list", params: %{}},
          MetadataServer,
          session_id
        )

      [tool, plain] = response["result"]["tools"]
      assert tool["title"] == "Look up a receipt"
      assert tool["annotations"] == %{"readOnlyHint" => true}
      refute Map.has_key?(plain, "title")
      refute Map.has_key?(plain, "annotations")
    end
  end
end

defmodule MetadataServer do
  @moduledoc false
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
