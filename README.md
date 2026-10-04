# SimpleMCP

A minimal, dependency-light MCP (Model Context Protocol) server library for Elixir.
It depends only on Plug.

## Usage

    defmodule MyApp.MCPServer do
      use SimpleMCP

      @impl true
      def server_info, do: {"My App", "1.0.0"}

      @impl true
      def tools do
        [SimpleMCP.Tool.new("greet", "Says hello", %{name: {:required, :string, description: "Name"}})]
      end

      @impl true
      def handle_tool_call("greet", %{"name" => name}), do: {:ok, "Hello, #{name}!"}
    end

Mount it in your router:

    forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer

## Optional features

Every option below is **off by default**. An app that does not set them, and does not
change its own server code, gets responses byte-identical to earlier releases.

### Stateless: no session store

    forward "/mcp", SimpleMCP.Plug, server: MyApp.MCPServer, stateless: true

The server never creates, stores, requires or returns an `Mcp-Session-Id`, so it runs
on several machines with no shared memory. `initialize`, `tools/list` and `tools/call`
each work on their own. GET and DELETE answer 405. A client that sends a session header
anyway is served and the header is ignored.

### Caller context: a tool knows who is calling

The host app puts the caller on the connection under the assign key `:simple_mcp_context`
before the plug runs. A server that defines `handle_tool_call/3` receives it:

    plug :put_mcp_caller

    def put_mcp_caller(conn, _opts) do
      assign(conn, :simple_mcp_context, conn.assigns.current_user)
    end

    @impl true
    def handle_tool_call("whoami", _args, user), do: {:ok, user.email}

A server that defines only `handle_tool_call/2` is called exactly as before.

### Tool titles and annotations

    SimpleMCP.Tool.new("lookup", "Looks up a receipt", %{},
      title: "Look up a receipt",
      annotations: [read_only: true, destructive: false, idempotent: true, open_world: false]
    )

`read_only`, `destructive`, `idempotent` and `open_world` are emitted as the MCP hints
`readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`. Only the hints you
give are emitted. A tool given neither has no `title` or `annotations` key at all.

### Structured content

A tool can return its own content list, which is passed through unchanged:

    def handle_tool_call("share", _args) do
      {:ok, {:content, [
        %{"type" => "text", "text" => "Saved."},
        %{"type" => "resource_link", "uri" => "https://example.com/r/7", "name" => "Open"}
      ]}}
    end

Binary, map and list returns are encoded exactly as before.

## Protocol versions

Negotiation accepts `2025-11-25` (the default), `2025-06-18` and `2025-03-26`. An unknown
version falls back to the default.

## Tests and checks

    mix format --check-formatted
    mix credo --strict
    mix compile --warnings-as-errors
    mix test
    mix dialyzer

`test/fixtures/aa2017e/` holds byte captures of the responses at commit aa2017e, and
`SimpleMCP.CompatFixtureTest` asserts that the default-option responses still match them.
