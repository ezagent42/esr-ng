defmodule Esr.Capability do
  @moduledoc """
  Capability — a Push-based authorization grant carried in `ctx.caps`.

  A capability matches an `Esr.Invocation` when all four fields match
  (with `:any` acting as wildcard for `kind` / `behavior` / `instance`).

  `revoke/2` is admin-protected per Decision #81: `user://admin`'s
  all-caps capability (`%Esr.Capability{kind: :any, behavior: :any,
  instance: :any, ...}` granted_by `system://bootstrap`) is a structural
  invariant and cannot be removed. The check lives here at the data-layer
  boundary so any caller path is forced through one chokepoint.
  """

  @enforce_keys [:kind, :behavior, :instance, :granted_by, :granted_at]
  defstruct [:kind, :behavior, :instance, :granted_by, :granted_at]

  @type t :: %__MODULE__{
          kind: atom() | :any,
          behavior: module() | :any,
          instance: URI.t() | :any,
          granted_by: URI.t(),
          granted_at: DateTime.t()
        }

  @doc """
  Does this capability authorize the given invocation?

  Matches kind (Kind type atom, e.g. `:echo`), behavior (module, e.g.
  `Esr.Behavior.Echo`), and instance (the target URI). `:any` matches
  everything in that position.
  """
  @spec matches?(t(), %{
          required(:kind) => atom(),
          required(:behavior) => module(),
          required(:instance) => URI.t()
        }) :: boolean()
  def matches?(%__MODULE__{} = cap, %{kind: k, behavior: b, instance: i}) do
    field_match?(cap.kind, k) and
      field_match?(cap.behavior, b) and
      field_match?(cap.instance, i)
  end

  defp field_match?(:any, _), do: true
  defp field_match?(same, same), do: true
  defp field_match?(_, _), do: false

  @doc """
  Remove a capability from a MapSet of caps.

  Refuses to remove the admin all-caps invariant — `user://admin`'s
  triple-`:any` capability granted_by `system://bootstrap` is structural
  per Decision #81 and would break the bootstrap principal.

  Returns `{:ok, new_caps}` on success, `{:error, :cannot_revoke_admin}`
  if the input cap is the admin all-caps invariant.
  """
  @spec revoke(MapSet.t(t()), t()) :: {:ok, MapSet.t(t())} | {:error, :cannot_revoke_admin}
  def revoke(%MapSet{} = caps, %__MODULE__{} = cap) do
    if admin_invariant?(cap) do
      {:error, :cannot_revoke_admin}
    else
      {:ok, MapSet.delete(caps, cap)}
    end
  end

  @doc false
  def admin_invariant?(%__MODULE__{
        kind: :any,
        behavior: :any,
        instance: :any,
        granted_by: %URI{scheme: "system", host: "bootstrap"}
      }),
      do: true

  def admin_invariant?(%__MODULE__{}), do: false
end
