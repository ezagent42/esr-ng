defmodule Esr.Test.TestBehavior do
  @moduledoc """
  Minimal Behavior used by Kind.Server / Invocation / Runtime tests.
  Lives under `test/support/` (compiled only in `:test` per
  `mix.exs` `elixirc_paths(:test)`).

  Action `:noop` updates the slice's `:count` field; action `:fail`
  returns `{:error, :test_failure}`.
  """

  @behaviour Esr.Behavior

  @impl Esr.Behavior
  def actions, do: [:noop, :fail, :raise]

  @impl Esr.Behavior
  def state_slice, do: :test

  @impl Esr.Behavior
  def init_slice(_args), do: %{count: 0, last_msg: nil}

  @impl Esr.Behavior
  def invoke(:noop, slice, %{msg: msg}, _ctx) do
    {:ok, %{slice | count: slice.count + 1, last_msg: msg}, %{echoed: msg}}
  end

  def invoke(:fail, _slice, _args, _ctx), do: {:error, :test_failure}

  def invoke(:raise, _slice, _args, _ctx), do: raise("boom")

  @impl Esr.Behavior
  def interface do
    %{
      noop: %{args: %{msg: :string}, returns: %{echoed: :string}, modes: [:call, :cast]},
      fail: %{args: %{}, returns: %{}, modes: [:call]},
      raise: %{args: %{}, returns: %{}, modes: [:call]}
    }
  end
end

defmodule Esr.Test.TestKind do
  @moduledoc "Minimal Kind that uses `Esr.Test.TestBehavior`."

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :test

  @impl Esr.Kind
  def behaviors, do: [Esr.Test.TestBehavior]

  @impl Esr.Kind
  def persistence, do: :ephemeral
end
