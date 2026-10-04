defmodule SimpleMCP.TestServer do
  @moduledoc """
  A minimal SimpleMCP server used as a fixture in the test suite.
  """

  use SimpleMCP

  @impl true
  def server_info, do: {"Test Server", "1.0.0"}

  @impl true
  def tools do
    [
      SimpleMCP.Tool.new("greet", "Says hello to someone", %{
        name: {:required, :string, description: "Name to greet"}
      }),
      SimpleMCP.Tool.new("add", "Adds two numbers", %{
        a: {:required, :integer, description: "First number"},
        b: {:required, :integer, description: "Second number"}
      }),
      SimpleMCP.Tool.new("echo", "Echoes back the input", %{
        message: {:required, :string, description: "Message to echo"}
      })
    ]
  end

  @impl true
  def handle_tool_call("greet", %{"name" => name}) do
    {:ok, "Hello, #{name}!"}
  end

  def handle_tool_call("add", %{"a" => a, "b" => b}) do
    {:ok, %{result: a + b}}
  end

  def handle_tool_call("echo", %{"message" => message}) do
    {:ok, message}
  end

  def handle_tool_call(name, _args) do
    {:error, "Unknown tool: #{name}"}
  end
end
