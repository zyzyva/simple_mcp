defmodule SimpleMCP.CompatFixtureTest do
  @moduledoc """
  Slice 318 acceptance criterion 1: the default-option responses are byte-identical to
  the library at commit aa2017e. The fixtures were captured there, before any change.
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.CompatScenario

  @fixtures Path.expand("../fixtures/aa2017e", __DIR__)

  # Protocol errors with no request id take a unique integer from the library, so
  # that one token differs on every run by design. Only it is normalised.
  @unique_error_id ~r/"err_\d+"/

  test "every default-option response matches the aa2017e capture byte for byte" do
    exchanges = CompatScenario.run()

    assert Enum.map(exchanges, & &1.name) == fixture_names()

    for exchange <- exchanges do
      assert render_headers(exchange) == read_fixture(exchange.name, "headers"),
             "headers differ for #{exchange.name}"

      assert normalise(exchange.body) == normalise(read_fixture(exchange.name, "body")),
             "body differs for #{exchange.name}"
    end
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

  defp render_headers(%{status: status, headers: headers}) do
    lines = Enum.map(headers, fn {key, value} -> "#{key}: #{value}\n" end)
    IO.iodata_to_binary(["status: #{status}\n" | lines])
  end

  defp normalise(text), do: Regex.replace(@unique_error_id, text, ~s("err_N"))
end
