defmodule SimpleMCP.ProtocolVersionTest do
  @moduledoc """
  Slice 318 behaviour 4: `2025-06-18` negotiates to itself, alongside the two versions
  already accepted. The default stays `2025-11-25`, and an unknown version still falls
  back to it.
  """
  use ExUnit.Case, async: true

  alias SimpleMCP.{Protocol, Session}

  describe "initialize negotiation" do
    test "2025-06-18 negotiates to itself" do
      assert negotiated_version("2025-06-18") == "2025-06-18"
    end

    test "the two versions already accepted still negotiate to themselves" do
      assert negotiated_version("2025-03-26") == "2025-03-26"
      assert negotiated_version("2025-11-25") == "2025-11-25"
    end

    test "an unknown version falls back to the default" do
      assert negotiated_version("2019-01-01") == "2025-11-25"
    end

    test "a missing version falls back to the default" do
      session_id = Session.generate_id()

      response =
        Protocol.handle_message(
          %{id: 1, method: "initialize", params: %{}},
          SimpleMCP.TestServer,
          session_id
        )

      assert response["result"]["protocolVersion"] == "2025-11-25"
    end
  end

  defp negotiated_version(version) do
    session_id = Session.generate_id()
    message = %{id: 1, method: "initialize", params: %{"protocolVersion" => version}}

    response = Protocol.handle_message(message, SimpleMCP.TestServer, session_id)
    response["result"]["protocolVersion"]
  end
end
