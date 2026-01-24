defmodule SimpleMCP do
  @moduledoc """
  A minimal MCP (Model Context Protocol) server library for Elixir.

  ## Usage

      defmodule MyApp.MCPServer do
        use SimpleMCP

        @impl true
        def server_info, do: {"My App", "1.0.0"}

        @impl true
        def tools do
          [
            SimpleMCP.Tool.new("greet", "Says hello", %{
              name: {:required, :string, description: "Name to greet"}
            })
          ]
        end

        @impl true
        def handle_tool_call("greet", %{"name" => name}) do
          {:ok, "Hello, \#{name}!"}
        end
      end

  Then in your router:

      forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer
  """

  @type tool_result :: {:ok, any()} | {:error, String.t()}

  @callback server_info() :: {name :: String.t(), version :: String.t()}
  @callback tools() :: [SimpleMCP.Tool.t()]
  @callback handle_tool_call(tool_name :: String.t(), arguments :: map()) :: tool_result()

  defmacro __using__(_opts) do
    quote do
      @behaviour SimpleMCP

      @impl true
      def server_info, do: {"SimpleMCP Server", "1.0.0"}

      @impl true
      def tools, do: []

      @impl true
      def handle_tool_call(_name, _args), do: {:error, "Not implemented"}

      defoverridable server_info: 0, tools: 0, handle_tool_call: 2
    end
  end
end
