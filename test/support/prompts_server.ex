defmodule SimpleMCP.PromptsServer do
  @moduledoc """
  A server that defines ALL the slice-424 callbacks: `instructions/0`, `prompts/0` and
  `get_prompt/3`. Besides the well-behaved prompts it holds one deliberately broken prompt for each
  way rendering can go wrong, so each must come back as a JSON-RPC error and never as a crash.
  """

  use SimpleMCP

  alias SimpleMCP.Prompt

  @impl true
  def server_info, do: {"Prompts Server", "1.0.0"}

  @impl true
  def instructions, do: "Be brief."

  @impl true
  def prompts do
    [
      Prompt.new("review",
        title: "Review my receipts",
        description: "Asks the assistant to look over flagged receipts",
        arguments: [
          topic: {:required, description: "What to review"},
          tone: {:optional, description: "How to say it"},
          focus: {:required, []}
        ]
      ),
      Prompt.new("plain"),
      Prompt.new("rich", description: "Mixed roles and content blocks"),
      Prompt.new("whoami", description: "Reports the caller"),
      Prompt.new("echo_args", arguments: [a: {:optional, []}]),
      Prompt.new("string_keys"),
      Prompt.new("error_text"),
      Prompt.new("error_term"),
      Prompt.new("boom"),
      Prompt.new("exits"),
      Prompt.new("throws"),
      Prompt.new("bad_result"),
      Prompt.new("bad_role"),
      Prompt.new("bad_content"),
      Prompt.new("bad_messages")
    ]
  end

  @impl true
  def get_prompt("review", %{"topic" => topic} = arguments, _context) do
    tone = Map.get(arguments, "tone", "plain")
    {:ok, [%{role: :user, content: "Please review #{topic}, #{tone}."}]}
  end

  def get_prompt("plain", _arguments, _context) do
    {:ok, [%{role: :user, content: "Hello"}]}
  end

  def get_prompt("rich", _arguments, _context) do
    {:ok,
     %{
       description: "A rich prompt",
       messages: [
         %{role: :user, content: %{type: "text", text: "Look at this"}},
         %{
           role: "assistant",
           content: %{"type" => "image", "data" => "AAAA", "mimeType" => "image/png"}
         },
         %{
           role: :user,
           content: %{
             type: "resource",
             resource: %{uri: "resource://x", mimeType: "text/plain", text: "body"}
           }
         }
       ]
     }}
  end

  def get_prompt("whoami", _arguments, context) do
    {:ok, [%{role: :user, content: "caller=#{inspect(context)}"}]}
  end

  def get_prompt("echo_args", arguments, _context) do
    {:ok, [%{role: :user, content: "args=#{inspect(arguments)}"}]}
  end

  def get_prompt("string_keys", _arguments, _context) do
    {:ok, [%{"role" => "user", "content" => "string keys work"}]}
  end

  def get_prompt("error_text", _arguments, _context), do: {:error, "No receipts to review"}
  def get_prompt("error_term", _arguments, _context), do: {:error, {:not_ready, 3}}
  def get_prompt("boom", _arguments, _context), do: raise("secret internal detail")
  def get_prompt("exits", _arguments, _context), do: exit(:shutdown)
  def get_prompt("throws", _arguments, _context), do: throw(:ball)
  def get_prompt("bad_result", _arguments, _context), do: :not_a_result

  def get_prompt("bad_role", _arguments, _context),
    do: {:ok, [%{role: :system, content: "nope"}]}

  def get_prompt("bad_content", _arguments, _context),
    do: {:ok, [%{role: :user, content: 42}]}

  def get_prompt("bad_messages", _arguments, _context), do: {:ok, "not a list"}
end

defmodule SimpleMCP.ListOnlyPromptsServer do
  @moduledoc """
  Defines `prompts/0` but not `get_prompt/3`: a server bug, answered with a JSON-RPC error.
  """

  use SimpleMCP

  @impl true
  def prompts, do: [SimpleMCP.Prompt.new("lonely")]
end

defmodule SimpleMCP.RaisingPromptsServer do
  @moduledoc """
  Defines `prompts/0` and it raises, so `prompts/list` must answer a JSON-RPC error.
  """

  use SimpleMCP

  @impl true
  def prompts, do: raise("prompts blew up")

  @impl true
  def get_prompt(_name, _arguments, _context), do: {:ok, []}
end

defmodule SimpleMCP.ReadmeServer do
  @moduledoc """
  The README's instructions and prompts examples, verbatim, so the documentation cannot drift from
  what the library does (see `SimpleMCP.PromptsTest`).
  """

  use SimpleMCP

  @impl true
  def instructions do
    "Ask the person before changing anything. Keep answers short."
  end

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

    {:ok, [%{role: :user, content: "Review #{user.email}'s flagged receipts from #{month}."}]}
  end
end
