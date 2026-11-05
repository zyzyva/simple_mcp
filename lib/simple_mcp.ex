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

  # `{:ok, {:content, blocks}}` (slice 318) passes the blocks through as the result's
  # content unchanged; any other `{:ok, value}` is encoded as before.
  @type tool_result :: {:ok, any()} | {:error, String.t()}

  @callback server_info() :: {name :: String.t(), version :: String.t()}
  @callback tools() :: [SimpleMCP.Tool.t()]
  @callback handle_tool_call(tool_name :: String.t(), arguments :: map()) :: tool_result()

  # Optional (slice 318): a server that defines it receives the caller's context, the
  # value the host app put on the connection under `:simple_mcp_context`.
  @callback handle_tool_call(
              tool_name :: String.t(),
              arguments :: map(),
              context :: term()
            ) :: tool_result()

  # Optional (slice 424): standing instructions for the assistant, carried in the `initialize`
  # result as `instructions` (MCP 2025-06-18). Not defaulted by `use SimpleMCP`: a server that
  # does not define it has no `instructions` key at all.
  @callback instructions() :: String.t() | nil

  # Optional (slice 424): prompts (MCP 2025-06-18). A server that defines `prompts/0` advertises
  # the `prompts` capability and answers `prompts/list`; `get_prompt/3` renders one by name with
  # the arguments the client sent and the caller's context (the same value `handle_tool_call/3`
  # receives). A server that defines neither is answered exactly as before: no capability, and
  # method-not-found for both methods.
  @type prompt_message :: %{
          required(:role) => :user | :assistant | String.t(),
          required(:content) => String.t() | map()
        }

  @type prompt_result ::
          {:ok, [prompt_message()]}
          | {:ok,
             %{required(:messages) => [prompt_message()], optional(:description) => String.t()}}
          | {:error, String.t()}

  @callback prompts() :: [SimpleMCP.Prompt.t()]
  @callback get_prompt(name :: String.t(), arguments :: map(), context :: term()) ::
              prompt_result()

  @optional_callbacks handle_tool_call: 3, instructions: 0, prompts: 0, get_prompt: 3

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
