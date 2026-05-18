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

  @type scope_tuple ::
          {:within_session, URI.t()}
          | {:spawned_by, URI.t()}

  @type t :: %__MODULE__{
          kind: atom() | :any,
          behavior: module() | :any,
          instance: URI.t() | :any | scope_tuple(),
          granted_by: URI.t(),
          granted_at: DateTime.t()
        }

  @doc """
  Does this capability authorize the given invocation?

  Matches kind (Kind type atom, e.g. `:echo`), behavior (module, e.g.
  `Esr.Behavior.Echo`), and instance (the target URI). `:any` matches
  everything in that position.

  ## Scope-bounded instance shapes (Phase 7 PR 42 / D7-3)

  The `instance` field may also be one of two tuple shapes that
  express bounded delegation:

  - `{:within_session, %URI{} = session_uri}` — matches when the
    needed cap's instance URI is `session_uri` itself or a sub-URI
    of it (prefix match on `URI.to_string/1`). Used by the
    orchestrator's scope-bounded delegation cap so it can act
    within its own session without becoming a full admin.

  - `{:spawned_by, %URI{} = principal_uri}` — matches when the
    needed cap's instance URI is in the lineage spawned by
    `principal_uri`. **PR 42 ships a structurally compliant
    placeholder that returns false** — actual lineage tracking
    arrives with PR 40 (`Esr.Entity.Agent.spawn/4` populates an
    `Agent.spawned_by` slice field) + a registry lookup wired
    here. Until PR 40, holding a `{:spawned_by, _}` cap matches
    nothing — denial defaults are correct.

  Both shapes preserve the existing CapBAC contract: the cap is
  more specific, not more permissive. Any cap with a scope tuple
  is bounded by the scope; `:any` remains the only true wildcard.

  ## Why the placeholder for `{:spawned_by, _}`

  Splitting the contract change (this PR) from the lineage
  registry (PR 40) keeps each PR small and reviewable. The
  contract is observable + tested NOW; the registry implementation
  + its tests land in PR 40 without re-touching `matches?/2`.
  """
  @spec matches?(t(), %{
          required(:kind) => atom(),
          required(:behavior) => module(),
          required(:instance) => URI.t()
        }) :: boolean()
  def matches?(%__MODULE__{} = cap, %{kind: k, behavior: b, instance: i}) do
    field_match?(cap.kind, k) and
      field_match?(cap.behavior, b) and
      instance_match?(cap.instance, i)
  end

  # Kind + behavior fields use plain `:any` or exact equality.
  defp field_match?(:any, _), do: true
  defp field_match?(same, same), do: true
  defp field_match?(_, _), do: false

  # Instance field additionally honors the two scope tuples (D7-3).
  defp instance_match?(:any, _), do: true

  defp instance_match?({:within_session, %URI{} = session_uri}, %URI{} = needed_instance) do
    needed_str = URI.to_string(needed_instance)
    session_str = URI.to_string(session_uri)

    # Match if needed URI is the session URI itself, or a sub-URI of
    # it (e.g. `session://main/behavior/chat/send` is within
    # `session://main`). String prefix is sufficient given URI
    # canonical form; we add a `/` boundary check to avoid false
    # positives like `session://main2` matching `{:within_session,
    # session://main}`.
    needed_str == session_str or
      String.starts_with?(needed_str, session_str <> "/")
  end

  defp instance_match?({:spawned_by, %URI{} = _principal_uri}, %URI{} = _needed_instance) do
    # PR 42 placeholder: returns false until PR 40 ships the
    # Agent.spawned_by slice field + lineage lookup registry.
    # Denying-by-default is the correct conservative behavior — a
    # principal holding a `{:spawned_by, X}` cap will simply find
    # all dispatches denied until the lineage data is available.
    # See moduledoc for the contract split rationale.
    false
  end

  defp instance_match?(same, same), do: true
  defp instance_match?(_, _), do: false

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

  @doc """
  Serialize a Capability to a JSON-safe map (for `users.caps_json`
  storage per Phase 4-completion Spec 05 Part A).

  Atoms become strings; modules become strings; URIs become strings.
  Inverse of `from_map/1`.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cap) do
    %{
      "kind" => atom_or_module_to_string(cap.kind),
      "behavior" => atom_or_module_to_string(cap.behavior),
      "instance" => uri_or_any_to_string(cap.instance),
      "granted_by" => uri_or_any_to_string(cap.granted_by),
      "granted_at" => DateTime.to_iso8601(cap.granted_at)
    }
  end

  @doc """
  Deserialize a Capability from a JSON-decoded map.
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = m) do
    %__MODULE__{
      kind: string_to_atom_or_module(Map.get(m, "kind")),
      behavior: string_to_atom_or_module(Map.get(m, "behavior")),
      instance: string_to_uri_or_any(Map.get(m, "instance")),
      granted_by: string_to_uri_or_any(Map.get(m, "granted_by")),
      granted_at: parse_datetime(Map.get(m, "granted_at"))
    }
  end

  defp atom_or_module_to_string(:any), do: "any"
  defp atom_or_module_to_string(value) when is_atom(value), do: Atom.to_string(value)

  defp string_to_atom_or_module("any"), do: :any
  defp string_to_atom_or_module(s) when is_binary(s) do
    cond do
      String.starts_with?(s, "Elixir.") ->
        String.to_existing_atom(s)

      Regex.match?(~r/^[a-z_][a-z0-9_]*$/, s) ->
        String.to_existing_atom(s)

      true ->
        String.to_existing_atom("Elixir." <> s)
    end
  rescue
    ArgumentError -> :any
  end

  defp uri_or_any_to_string(:any), do: "any"
  defp uri_or_any_to_string(%URI{} = u), do: URI.to_string(u)

  defp string_to_uri_or_any("any"), do: :any
  defp string_to_uri_or_any(s) when is_binary(s), do: URI.parse(s)

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  @doc """
  Compute the `needed` cap shape for a given (Kind module, action,
  target URI) tuple — for dispatch step 5.5 to feed into `matches?/2`.

  Phase 3d (P3-D6 hard flip + #P1-8): the target URI is required so
  we can extract the `instance` part (e.g. `session://main` from
  `session://main/behavior/chat/send`). `behavior` is looked up via
  `BehaviorRegistry.lookup(kind_module, action)` — same lookup
  `Kind.Runtime` does for invoke routing.

  Returns the 3-field map `Capability.matches?/2` expects:
  `%{kind: atom, behavior: module, instance: %URI{}}`.
  """
  @spec cap_for_action(module(), atom(), URI.t()) :: %{
          kind: atom(),
          behavior: module(),
          instance: URI.t()
        }
  def cap_for_action(kind_module, action, %URI{} = target_uri)
      when is_atom(kind_module) and is_atom(action) do
    behavior =
      case Esr.BehaviorRegistry.lookup(kind_module, action) do
        {:ok, behavior_module} -> behavior_module
        :error -> :unknown
      end

    %{
      kind: kind_module.type_name(),
      behavior: behavior,
      instance: Esr.URI.instance(target_uri)
    }
  end
end
