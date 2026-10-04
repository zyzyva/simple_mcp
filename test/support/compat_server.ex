defmodule SimpleMCP.CompatServer do
  @moduledoc """
  A server written the way every consuming app writes one today: the two-argument
  `handle_tool_call/2`, plain tools, no titles, no annotations. Slice 318 must leave
  its responses byte-identical, so it is the fixture the compatibility scenario drives.
  """

  use SimpleMCP

  @impl true
  def server_info, do: {"Compat Server", "1.0.0"}

  @impl true
  def tools do
    [
      SimpleMCP.Tool.new("greet", "Says hello to someone", %{
        name: {:required, :string, description: "Name to greet"}
      }),
      SimpleMCP.Tool.new("add", "Adds two numbers", %{
        a: {:required, :integer, description: "First number"},
        b: {:optional, :integer, description: "Second number"}
      })
    ]
  end

  @impl true
  def handle_tool_call("greet", %{"name" => name}), do: {:ok, "Hello, #{name}!"}
  def handle_tool_call("add", %{"a" => a} = arguments), do: {:ok, %{result: a + arguments["b"]}}
  def handle_tool_call("list", _args), do: {:ok, [1, 2, 3]}
  def handle_tool_call("number", _args), do: {:ok, 42}
  def handle_tool_call(name, _args), do: {:error, "Unknown tool: #{name}"}
end
