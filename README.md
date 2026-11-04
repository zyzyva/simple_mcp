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

### Standing instructions

A server can give the assistant standing instructions, sent once when the connection starts.
Define `instructions/0`:

    @impl true
    def instructions do
      "Ask the person before changing anything. Keep answers short."
    end

The `initialize` result then carries it as `instructions`. A server that does not define
`instructions/0` (or returns `nil`) has no `instructions` key at all. Something that is not a
string is a server bug: it is left out, logged, and the handshake still succeeds.

### Prompts

A server can offer prompts: named, ready-made requests a person picks from the assistant's
interface. Define `prompts/0` to list them and `get_prompt/3` to render one:

    @impl true
    def prompts do
      [
        SimpleMCP.Prompt.new("review_flagged",
          title: "Review my flagged receipts",
          description: "Go through the receipts that need a second look",
          arguments: [
            month: {:optional, description: "Which month, like 2026-09"}
          ]
        )
      ]
    end

    @impl true
    def get_prompt("review_flagged", arguments, user) do
      month = Map.get(arguments, "month", "this month")

      {:ok,
       [%{role: :user, content: "Review #{user.email}'s flagged receipts from #{month}."}]}
    end

`get_prompt/3` receives the prompt's name, the arguments the client sent (a map of strings)
and the caller's context, the same value `handle_tool_call/3` receives (the
`:simple_mcp_context` assign, see above), so a prompt can be tailored to the connected person.
It returns:

  * `{:ok, messages}`, or `{:ok, %{description: "...", messages: messages}}`. A message is
    `%{role: :user | :assistant, content: content}`, where `content` is a string (sent as a
    text block) or an MCP content block map (`%{type: "image", data: ..., mimeType: ...}`, a
    resource, and so on), sent as given. Atom or string keys both work.
  * `{:error, "text"}`, which the client receives as a JSON-RPC internal error carrying that
    text.

A server that defines `prompts/0` advertises the `prompts` capability in `initialize` (without
`listChanged`) and answers `prompts/list` and `prompts/get`, following the same session rule as
`tools/list`. A server that does not define it advertises nothing, and answers both methods
with method-not-found, exactly as before.

A missing required argument, an unknown prompt, arguments that are not an object, an `{:error, _}`,
a result that is not valid, and any raise, exit or throw in your callback are all proper
JSON-RPC errors (`-32602` invalid params, `-32603` internal error), never a crash and never an
HTTP 500. The detail of a raise is logged and is not sent to the client.

`SimpleMCP.Prompt.new/2` raises `ArgumentError` for a definition it cannot emit (a bad
argument shape, an unknown option), when the prompt is built.

### Which MCP revision each field comes from

Everything in this section follows the MCP specification revision **2025-06-18**, which this
library negotiates:

| Field | Where it comes from in 2025-06-18 |
| --- | --- |
| `instructions` in the `initialize` result | Base protocol, lifecycle: `InitializeResult.instructions` |
| `capabilities.prompts` (an empty object here) | Base protocol, lifecycle: `ServerCapabilities.prompts`; server/prompts: Capabilities |
| `prompts/list` and its `prompts` result | Server features, prompts: Listing Prompts |
| `Prompt`: `name`, `title`, `description`, `arguments` | Server features, prompts: Data Types, Prompt |
| `PromptArgument`: `name`, `description`, `required` | Server features, prompts: Listing Prompts |
| `prompts/get`, `name`, `arguments`, and the `description` and `messages` result | Server features, prompts: Getting a Prompt |
| `PromptMessage`: `role` (`user` or `assistant`) and `content` (text, image, audio, embedded resource) | Server features, prompts: Data Types, PromptMessage |
| Error codes `-32602` (invalid prompt name, missing required argument) and `-32603` (internal) | Server features, prompts: Error Handling |

Not included: `listChanged` and the `notifications/prompts/list_changed` notification,
pagination (`prompts/list` always returns the whole list and never a `nextCursor`; a `cursor`
from the client is ignored), argument completion, resources and sampling.

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

`test/fixtures/52e7f0c/` holds byte captures from commit 52e7f0c, taken before instructions and
prompts existed, of a server that defines neither (`SimpleMCP.CompatServer`) answering
`initialize`, `tools/list`, `prompts/list` and `prompts/get`, in the default session mode, in
stateless mode and with a caller context. `SimpleMCP.CompatMasterTest` asserts that every byte
still matches, so a server that upgrades without defining the new callbacks answers exactly as
it did.
