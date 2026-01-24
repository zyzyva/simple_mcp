defmodule SimpleMCP.Tool do
  @moduledoc """
  Defines a tool that can be called via MCP.

  ## Schema DSL

  The input_schema uses a simple DSL:

      %{
        name: {:required, :string, description: "User's name"},
        age: {:optional, :integer, description: "User's age"},
        tags: {:optional, :array, description: "List of tags"}
      }

  Supported types: :string, :integer, :number, :boolean, :array, :object
  """

  @type schema_type :: :string | :integer | :number | :boolean | :array | :object
  @type field_def :: {:required | :optional, schema_type(), keyword()}

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  defstruct [:name, :description, :input_schema]

  @doc """
  Creates a new tool definition.
  """
  def new(name, description, input_schema \\ %{}) do
    %__MODULE__{
      name: name,
      description: description,
      input_schema: input_schema
    }
  end

  @doc """
  Converts the tool to MCP JSON schema format.
  """
  def to_mcp_format(%__MODULE__{} = tool) do
    %{
      "name" => tool.name,
      "description" => tool.description,
      "inputSchema" => build_json_schema(tool.input_schema)
    }
  end

  defp build_json_schema(schema) when is_map(schema) do
    {properties, required} =
      Enum.reduce(schema, {%{}, []}, fn {key, value}, {props, req} ->
        key_str = to_string(key)
        {requirement, type, opts} = parse_field_def(value)

        prop = %{
          "type" => type_to_json_type(type)
        }

        prop =
          case Keyword.get(opts, :description) do
            nil -> prop
            desc -> Map.put(prop, "description", desc)
          end

        new_props = Map.put(props, key_str, prop)

        new_req =
          case requirement do
            :required -> [key_str | req]
            :optional -> req
          end

        {new_props, new_req}
      end)

    result = %{
      "type" => "object",
      "properties" => properties
    }

    case required do
      [] -> result
      _ -> Map.put(result, "required", Enum.reverse(required))
    end
  end

  defp build_json_schema(_), do: %{"type" => "object", "properties" => %{}}

  defp parse_field_def({requirement, type, opts}) when is_list(opts) do
    {requirement, type, opts}
  end

  defp parse_field_def({requirement, type}) do
    {requirement, type, []}
  end

  defp parse_field_def(value) do
    {:optional, :string, [description: inspect(value)]}
  end

  defp type_to_json_type(:string), do: "string"
  defp type_to_json_type(:integer), do: "integer"
  defp type_to_json_type(:number), do: "number"
  defp type_to_json_type(:boolean), do: "boolean"
  defp type_to_json_type(:array), do: "array"
  defp type_to_json_type(:object), do: "object"
  defp type_to_json_type(_), do: "string"
end
