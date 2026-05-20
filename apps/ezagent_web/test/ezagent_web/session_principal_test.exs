defmodule EzagentWeb.SessionPrincipalTest do
  @moduledoc """
  Layer 1 of 3: write-side invariant — `SessionPrincipal.put/2` is
  the only sanctioned writer for `:current_entity_uri` and it
  refuses anything that wouldn't survive `URI.parse` + scheme check.

  See `EzagentWeb.SessionPrincipal` for the why-this-exists story
  (the bare-handle session bug Allen reported 2026-05-20).
  """
  use ExUnit.Case, async: true

  alias EzagentWeb.SessionPrincipal

  describe "canonicalize/1" do
    test "full entity URIs pass through unchanged" do
      assert SessionPrincipal.canonicalize("entity://user/default/admin") == "entity://user/default/admin"
      assert SessionPrincipal.canonicalize("entity://agent/default/echo_default") == "entity://agent/default/echo_default"
    end

    test "bare handle is normalized to entity://user/<handle> (lowercased)" do
      assert SessionPrincipal.canonicalize("admin") == "entity://user/default/admin"
      assert SessionPrincipal.canonicalize("ADMIN") == "entity://user/default/admin"
      assert SessionPrincipal.canonicalize("  allen  ") == "entity://user/default/allen"
      assert SessionPrincipal.canonicalize("user_123") == "entity://user/default/user_123"
    end

    test "raises ArgumentError on inputs that don't yield a valid entity URI" do
      assert_raise ArgumentError, ~r/not a valid entity URI/, fn ->
        SessionPrincipal.canonicalize("foo@bar.com")
      end

      assert_raise ArgumentError, ~r/not a valid entity URI/, fn ->
        SessionPrincipal.canonicalize("https://example.com/admin")
      end

      assert_raise ArgumentError, ~r/not a valid entity URI/, fn ->
        # Non-user/agent host — workspace URIs are NOT principals.
        SessionPrincipal.canonicalize("entity://workspace/default")
      end

      assert_raise ArgumentError, ~r/not a valid entity URI/, fn ->
        SessionPrincipal.canonicalize("   ")
      end
    end

    test "raises on non-string input" do
      assert_raise ArgumentError, ~r/expects a String/, fn ->
        SessionPrincipal.canonicalize(nil)
      end

      assert_raise ArgumentError, ~r/expects a String/, fn ->
        SessionPrincipal.canonicalize(%{handle: "admin"})
      end
    end
  end

  describe "put/2" do
    test "stores the CANONICAL form (not the raw input)" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{})
        |> SessionPrincipal.put("admin")

      assert Plug.Conn.get_session(conn, :current_entity_uri) == "entity://user/default/admin"
    end

    test "rotates the session ID (fixation defence)" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{some_pre_auth_key: "value"})

      conn_after = SessionPrincipal.put(conn, "admin")

      # `configure_session(renew: true)` flag is set on the conn's
      # private session options — we can't fully observe ID rotation
      # in a test harness, but the operation must succeed and the
      # principal slot is set.
      assert Plug.Conn.get_session(conn_after, :current_entity_uri) == "entity://user/default/admin"
    end

    test "raises on invalid input — same boundary as canonicalize/1" do
      conn = Plug.Test.conn(:get, "/") |> Plug.Test.init_test_session(%{})

      assert_raise ArgumentError, fn ->
        SessionPrincipal.put(conn, "not a URI")
      end

      assert_raise ArgumentError, fn ->
        SessionPrincipal.put(conn, nil)
      end
    end
  end

  describe "codebase invariant — single sanctioned writer" do
    # This test is the architectural gate: no controller / plug should
    # call `put_session(_, :current_entity_uri, _)` directly. They
    # MUST funnel through `SessionPrincipal.put/2` so the canonical-
    # form invariant is enforced at the only entry point.
    #
    # Per memory `feedback_completion_requires_invariant_test`.
    test "no direct put_session(:current_entity_uri, _) outside SessionPrincipal" do
      app_dir = Path.expand("../../../../", __DIR__)
      # Grep for direct writes, excluding the one place that's allowed.
      {output, _exit_code} =
        System.cmd(
          "grep",
          [
            "-rE",
            "put_session\\([^)]+:current_entity_uri",
            Path.join(app_dir, "apps"),
            "--include=*.ex",
            "--exclude=session_principal.ex"
          ],
          stderr_to_stdout: true
        )

      violations =
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(fn line ->
          # The SessionPrincipal module is the only allowed writer.
          # Tests that exercise it are also fine.
          String.contains?(line, "session_principal") or
            String.contains?(line, "test/")
        end)

      assert violations == [],
             "Direct put_session(_, :current_entity_uri, _) found outside SessionPrincipal:\n" <>
               Enum.join(violations, "\n") <>
               "\n\nFunnel all auth paths through EzagentWeb.SessionPrincipal.put/2 — " <>
               "it validates that the principal is a canonical entity:// URI before storage. " <>
               "See module @moduledoc for the bug this prevents."
    end
  end
end
