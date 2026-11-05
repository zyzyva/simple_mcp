defmodule SimpleMCP.InstructionsServer do
  @moduledoc """
  A server that defines the optional `instructions/0` callback (slice 424) and nothing else new.
  """

  use SimpleMCP

  @impl true
  def server_info, do: {"Instructions Server", "1.0.0"}

  @impl true
  def instructions do
    "Always ask the person before changing anything.\nPrefer short answers. Naïve café ✓"
  end
end

defmodule SimpleMCP.NilInstructionsServer do
  @moduledoc """
  Defines `instructions/0` but has nothing to say right now (it returns nil), so the result
  must carry no `instructions` key, exactly as if the callback were not defined.
  """

  use SimpleMCP

  @impl true
  def instructions, do: nil
end

defmodule SimpleMCP.BadInstructionsServer do
  @moduledoc """
  Defines `instructions/0` and returns something that is not a string. A server bug must not
  take the `initialize` handshake down, so the result carries no `instructions` key.
  """

  use SimpleMCP

  @impl true
  def instructions, do: %{not: "a string"}
end
