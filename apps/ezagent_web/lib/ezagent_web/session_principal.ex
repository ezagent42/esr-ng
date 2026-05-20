defmodule EzagentWeb.SessionPrincipal do
  @moduledoc """
  The single authorized writer for the session `:current_entity_uri`
  key. Forces every auth path (password, magic link, registration,
  and whatever lands next — OAuth, WebAuthn, SAML) through one
  validating funnel.

  Allen 2026-05-20: the bare-handle login bug shipped because
  `session_controller.credentials_create` normalized its input for
  the auth check but then `put_session(:current_entity_uri, raw)`
  wrote the unnormalized string. The downstream
  `EzagentWeb.Plugs.RequireEntity` parsed it as a URI, found no
  scheme, and bounced to /login — login appeared to fail.

  This module prevents that class of bug architecturally rather than
  by remembering. `put/2` validates that the input normalizes to a
  parseable `entity://user/...` or `entity://agent/...` URI and
  RAISES `ArgumentError` if not. There is no `:ok | :error` tuple
  to forget to handle and no fallback that silently writes garbage.
  Per memory `feedback_let_it_crash_no_workarounds`.

  Convention: NO direct `put_session(conn, :current_entity_uri, _)`
  call is allowed anywhere else in the codebase. A test asserts this
  invariant.
  """

  import Plug.Conn, only: [put_session: 3, configure_session: 2]

  @valid_hosts ["user", "agent"]

  @doc """
  Stores a canonical `entity://...` URI string in the session's
  `:current_entity_uri` slot. Accepts:

  - a full URI string (`"entity://user/admin"`) — passes through
  - a bare handle (`"admin"`, `"allen"`) — normalized to
    `"entity://user/<handle>"` (lowercased)

  Raises `ArgumentError` if the result is not a parseable
  `entity://user/...` or `entity://agent/...` URI. The session is
  also rotated via `configure_session(renew: true)` so a stolen
  pre-auth session ID cannot be reused.
  """
  @spec put(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put(conn, raw) when is_binary(raw) do
    canonical = canonicalize(raw)

    conn
    |> configure_session(renew: true)
    |> put_session(:current_entity_uri, canonical)
  end

  def put(_conn, other) do
    raise ArgumentError,
          "EzagentWeb.SessionPrincipal.put/2 expects a String principal, got: #{inspect(other)}"
  end

  @doc """
  Returns the canonical entity URI string for `raw`. Same validation
  as `put/2` but pure — useful for tests and for code paths that
  need to construct the canonical form without writing to a session
  yet.

  Raises `ArgumentError` on invalid input.
  """
  @spec canonicalize(String.t()) :: String.t()
  def canonicalize(raw) when is_binary(raw) do
    candidate = normalize(raw)

    case URI.parse(candidate) do
      %URI{scheme: "entity", host: host} when host in @valid_hosts ->
        candidate

      _ ->
        raise ArgumentError,
              "EzagentWeb.SessionPrincipal: not a valid entity URI: #{inspect(raw)} " <>
                "(normalized to #{inspect(candidate)}). Expected entity://user/... or entity://agent/..."
    end
  end

  def canonicalize(other) do
    raise ArgumentError,
          "EzagentWeb.SessionPrincipal.canonicalize/1 expects a String, got: #{inspect(other)}"
  end

  defp normalize(input) do
    trimmed = String.trim(input)

    cond do
      String.starts_with?(trimmed, "entity://") ->
        trimmed

      String.match?(trimmed, ~r/^[a-zA-Z0-9_-]+$/) ->
        "entity://user/" <> String.downcase(trimmed)

      true ->
        trimmed
    end
  end
end
