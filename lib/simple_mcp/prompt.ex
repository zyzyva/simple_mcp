defmodule SimpleMCP.Prompt do
  @moduledoc """
  Defines a prompt a server offers (slice 424), in the shape of MCP 2025-06-18's `Prompt` and
  `PromptArgument`.

  A prompt has a name, an optional title and description, and a list of arguments. Each argument
  has a name, an optional description and whether it is required. Every argument value a client
  sends is a string, so an argument has no type.

      SimpleMCP.Prompt.new("review",
        title: "Review my receipts",
        description: "Asks the assistant to look over the flagged ones",
        arguments: [
          topic: {:required, description: "What to review"},
          tone: {:optional, description: "How to say it"}
        ]
      )

  Give `:arguments` as a keyword list (or a list of `{name, {requirement, opts}}` pairs) to keep
  the order a client shows them in. A definition that cannot be emitted raises `ArgumentError` when
  the prompt is built, never when a client asks.
  """

  @type argument :: %{
          name: String.t(),
          description: String.t() | nil,
          required: boolean()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          arguments: [argument()]
        }

  defstruct [:name, :title, :description, arguments: []]

  @options [:title, :description, :arguments]

  @doc """
  Creates a prompt definition.

  Options, all optional:

    * `:title` - a human-readable name, emitted as `title`.
    * `:description` - emitted as `description`.
    * `:arguments` - a list of `{name, {:required | :optional, opts}}`, where `opts` may hold a
      `:description`. A name is a string or an atom.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ [])

  def new(name, opts) when is_binary(name) do
    check_options!(opts)

    %__MODULE__{
      name: name,
      title: Keyword.get(opts, :title),
      description: Keyword.get(opts, :description),
      arguments: opts |> Keyword.get(:arguments, []) |> Enum.map(&argument!/1)
    }
  end

  def new(name, _opts) do
    raise ArgumentError, "prompt name must be a string, got: #{inspect(name)}"
  end

  @doc """
  Converts the prompt to the MCP `Prompt` object. Only what was given is emitted, and an empty
  argument list counts as none.
  """
  @spec to_mcp_format(t()) :: map()
  def to_mcp_format(%__MODULE__{} = prompt) do
    base = %{"name" => prompt.name}

    base
    |> put_when_set("title", prompt.title)
    |> put_when_set("description", prompt.description)
    |> put_arguments(prompt.arguments)
  end

  @doc """
  The names of the required arguments `arguments` does not supply, in definition order. A required
  argument sent as null counts as missing; an empty string does not.
  """
  @spec missing_arguments(t(), map()) :: [String.t()]
  def missing_arguments(%__MODULE__{arguments: arguments}, given) when is_map(given) do
    for %{name: name, required: true} <- arguments, Map.get(given, name) == nil, do: name
  end

  defp put_when_set(map, _key, nil), do: map
  defp put_when_set(map, key, value), do: Map.put(map, key, value)

  defp put_arguments(map, []), do: map

  defp put_arguments(map, arguments),
    do: Map.put(map, "arguments", Enum.map(arguments, &mcp_argument/1))

  defp mcp_argument(%{name: name, description: description, required: required}) do
    put_when_set(%{"name" => name, "required" => required}, "description", description)
  end

  defp check_options!(opts) do
    case Keyword.keys(opts) -- @options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown option(s) for a prompt: #{inspect(unknown)}"
    end
  end

  defp argument!({name, {requirement, opts}})
       when (is_binary(name) or is_atom(name)) and requirement in [:required, :optional] and
              is_list(opts) do
    %{
      name: to_string(name),
      description: Keyword.get(opts, :description),
      required: requirement == :required
    }
  end

  defp argument!({name, {requirement, _opts}}) when is_binary(name) or is_atom(name) do
    raise ArgumentError,
          "prompt argument #{inspect(name)} must be :required or :optional, got: " <>
            inspect(requirement)
  end

  defp argument!(other) do
    raise ArgumentError,
          "a prompt argument must be {name, {:required | :optional, opts}}, got: #{inspect(other)}"
  end
end
