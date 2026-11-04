defmodule SimpleMCP.CompatMasterTest do
  @moduledoc """
  Slice 424 acceptance criterion, the key pin: a server that defines neither the new callbacks
  (`instructions/0`, `prompts/0`, `get_prompt/3`) answers byte for byte as it did on the library at
  commit 52e7f0c, the master this slice branched from. `SimpleMCP.CompatServer` is written the way every
  consuming app writes a server today, and is driven through `initialize`, `tools/list`, `prompts/list`
  and `prompts/get`, in the default session mode, in `stateless: true` mode, and with a caller context.

  The fixtures were captured from 52e7f0c BEFORE any slice-424 change (see `SimpleMCP.CompatScenario424`).
  Their prompts answers are the method-not-found errors a server with no prompts gives, which is exactly
  what must not change. The test fails on any added key, any reordered key, any changed header, and any
  capability the server did not ask for.
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.CompatScenario424

  @fixtures Path.expand("../fixtures/52e7f0c", __DIR__)

  # Protocol errors with no request id take a unique integer from the library, so that one token
  # differs on every run by design. Only it is normalised.
  @unique_error_id ~r/"err_\d+"/

  test "a server with no instructions and no prompts answers as 52e7f0c did, byte for byte" do
    exchanges = CompatScenario424.run()

    assert Enum.map(exchanges, & &1.name) == fixture_names()

    for exchange <- exchanges do
      assert CompatScenario424.render_headers(exchange) == read_fixture(exchange.name, "headers"),
             "headers differ for #{exchange.name}"

      assert normalise(exchange.body) == normalise(read_fixture(exchange.name, "body")),
             "body differs for #{exchange.name}"
    end
  end

  test "the capture is not vacuous: it holds the exchanges the slice cares about" do
    names = fixture_names()

    for expected <- [
          "01_initialize_2025_06_18",
          "05_tools_list",
          "07_prompts_list",
          "08_prompts_get"
        ] do
      assert expected in names
    end

    # With no prompts a server answers method-not-found for both and advertises no capability.
    assert read_fixture("07_prompts_list", "body") =~ "Method not found: prompts/list"
    assert read_fixture("08_prompts_get", "body") =~ "Method not found: prompts/get"
    refute read_fixture("01_initialize_2025_06_18", "body") =~ "prompts"
    refute read_fixture("01_initialize_2025_06_18", "body") =~ "instructions"
  end

  defp fixture_names do
    @fixtures
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".headers"))
    |> Enum.map(&Path.rootname/1)
    |> Enum.sort()
  end

  defp read_fixture(name, extension) do
    @fixtures |> Path.join("#{name}.#{extension}") |> File.read!()
  end

  defp normalise(text), do: Regex.replace(@unique_error_id, text, ~s("err_N"))
end
