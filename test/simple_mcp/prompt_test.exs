defmodule SimpleMCP.PromptTest do
  @moduledoc """
  Slice 424: the `SimpleMCP.Prompt` struct and its MCP 2025-06-18 shape (`Prompt`, `PromptArgument`).
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.Prompt

  describe "new/2 and to_mcp_format/1" do
    test "a prompt with only a name is emitted with only a name" do
      assert Prompt.to_mcp_format(Prompt.new("plain")) == %{"name" => "plain"}
    end

    test "title and description are emitted when given, and only then" do
      prompt = Prompt.new("p", title: "A title", description: "A description")

      assert Prompt.to_mcp_format(prompt) == %{
               "name" => "p",
               "title" => "A title",
               "description" => "A description"
             }

      assert Prompt.to_mcp_format(Prompt.new("p", title: "T")) == %{"name" => "p", "title" => "T"}
    end

    test "arguments are emitted in the order given, each with its required flag" do
      prompt =
        Prompt.new("review",
          arguments: [
            topic: {:required, description: "What to review"},
            tone: {:optional, description: "How to say it"},
            focus: {:required, []}
          ]
        )

      assert Prompt.to_mcp_format(prompt)["arguments"] == [
               %{"name" => "topic", "description" => "What to review", "required" => true},
               %{"name" => "tone", "description" => "How to say it", "required" => false},
               %{"name" => "focus", "required" => true}
             ]
    end

    test "an empty argument list counts as none: no arguments key at all" do
      refute Map.has_key?(Prompt.to_mcp_format(Prompt.new("p", arguments: [])), "arguments")
    end

    test "argument names may be atoms or strings" do
      prompt = Prompt.new("p", arguments: [{"city", {:required, []}}, {:zip, {:optional, []}}])

      assert Enum.map(Prompt.to_mcp_format(prompt)["arguments"], & &1["name"]) == ["city", "zip"]
    end

    test "the struct holds what was given" do
      prompt = Prompt.new("p", title: "T", description: "D", arguments: [a: {:required, []}])

      assert %Prompt{name: "p", title: "T", description: "D"} = prompt
      assert [%{name: "a", required: true}] = prompt.arguments
    end
  end

  describe "a malformed definition fails when the prompt is built, not when a client asks" do
    test "an argument that is neither required nor optional" do
      assert_raise ArgumentError, ~r/must be :required or :optional/, fn ->
        Prompt.new("p", arguments: [a: {:mandatory, []}])
      end
    end

    test "an argument that is not a name and a requirement" do
      assert_raise ArgumentError, ~r/argument/, fn ->
        Prompt.new("p", arguments: [:just_a_name])
      end
    end

    test "a name that is not a string" do
      assert_raise ArgumentError, ~r/name/, fn -> Prompt.new(:atom_name) end
    end

    test "an unknown option" do
      assert_raise ArgumentError, ~r/unknown option/, fn -> Prompt.new("p", colour: "red") end
    end
  end

  describe "missing_arguments/2" do
    setup do
      %{
        prompt:
          Prompt.new("p",
            arguments: [a: {:required, []}, b: {:optional, []}, c: {:required, []}]
          )
      }
    end

    test "names the required arguments that are absent, in definition order", %{prompt: prompt} do
      assert Prompt.missing_arguments(prompt, %{}) == ["a", "c"]
      assert Prompt.missing_arguments(prompt, %{"c" => "x"}) == ["a"]
    end

    test "an optional argument is never missing", %{prompt: prompt} do
      assert Prompt.missing_arguments(prompt, %{"a" => "1", "c" => "2"}) == []
    end

    test "a required argument given as null counts as missing, an empty string does not", %{
      prompt: prompt
    } do
      assert Prompt.missing_arguments(prompt, %{"a" => nil, "c" => ""}) == ["a"]
    end
  end
end
