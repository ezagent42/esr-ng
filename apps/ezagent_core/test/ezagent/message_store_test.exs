defmodule Ezagent.MessageStoreTest do
  @moduledoc """
  Phase 2 2a-step 3: MessageStore CRUD + query tests.

  Sandbox-mode integration against the SQLite Repo. Validates the 4
  public functions (write/2, in_session_since/2, recent_in_session/2,
  by_uri/1) including rejoin-replay edge cases (strict-after timestamp
  semantics) and the @replay_cap bound.
  """

  use ExUnit.Case
  alias Ezagent.{Message, MessageStore}
  alias EzagentCore.Repo

  @session_a URI.new!("session://main")
  @session_b URI.new!("session://other")
  @admin URI.new!("user://admin")
  @bot URI.new!("agent://cc-builder")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp insert_msg(sender, session, body_text, opts \\ []) do
    msg = Message.new(sender, %{text: body_text, attachments: []}, opts)
    {:ok, written} = MessageStore.write(msg, session)
    written
  end

  describe "write/2" do
    test "persists message with caller-supplied session_uri" do
      msg = Message.new(@admin, %{text: "hi", attachments: []})
      {:ok, written} = MessageStore.write(msg, @session_a)

      assert written.session_uri == @session_a
      assert written.sender == @admin

      # Round-trip load to confirm SQLite saw it (not just changeset roundtrip).
      assert {:ok, loaded} = MessageStore.by_uri(msg.uri)
      assert loaded.session_uri == @session_a
    end

    test "preserves the Message envelope unchanged (identity invariant)" do
      mention = URI.new!("agent://cc-builder")
      ref = URI.new!("message://aabbccdd00000000")

      msg =
        Message.new(@admin, %{text: "carry-through", attachments: []},
          mentions: [mention],
          ref: ref
        )

      {:ok, written} = MessageStore.write(msg, @session_a)

      # `session_uri` is metadata stamped at write boundary; sender / body /
      # mentions / ref / uri / inserted_at all unchanged (Decision #40 —
      # Message identity invariant).
      assert written.uri == msg.uri
      assert written.sender == msg.sender
      assert written.mentions == [mention]
      assert written.body == msg.body
      assert written.ref == ref
      assert written.inserted_at == msg.inserted_at
    end
  end

  describe "by_uri/1" do
    test "returns {:ok, message} for stored uri" do
      msg = insert_msg(@admin, @session_a, "lookup-me")
      assert {:ok, loaded} = MessageStore.by_uri(msg.uri)
      assert loaded.uri == msg.uri
    end

    test "returns :error for missing uri" do
      assert :error = MessageStore.by_uri("message://0000000000000000")
    end
  end

  describe "recent_in_session/2" do
    test "returns descending by inserted_at, bounded by limit, scoped to session" do
      now = DateTime.utc_now()

      # 3 messages in session_a at distinct times
      m1 =
        insert_msg(@admin, @session_a, "first", inserted_at: DateTime.add(now, -300, :second))

      m2 =
        insert_msg(@admin, @session_a, "second", inserted_at: DateTime.add(now, -200, :second))

      m3 =
        insert_msg(@bot, @session_a, "third", inserted_at: DateTime.add(now, -100, :second))

      # 1 message in session_b — must NOT leak into session_a query
      _other = insert_msg(@admin, @session_b, "other-session")

      result = MessageStore.recent_in_session(@session_a, 10)
      uris = Enum.map(result, & &1.uri)

      assert uris == [m3.uri, m2.uri, m1.uri]
    end

    test "respects limit" do
      now = DateTime.utc_now()

      for i <- 1..5 do
        insert_msg(@admin, @session_a, "msg-#{i}",
          inserted_at: DateTime.add(now, -i * 10, :second)
        )
      end

      result = MessageStore.recent_in_session(@session_a, 3)
      assert length(result) == 3
    end
  end

  describe "older_than/3 (Phase 5 PR 5 pagination)" do
    test "100-message back-pagination matches spec invariant (51-100 then 1-50)" do
      base = ~U[2026-05-17 10:00:00.000000Z]

      written =
        for i <- 1..100 do
          insert_msg(@admin, @session_a, "msg-#{i}",
            inserted_at: DateTime.add(base, i, :second)
          )
        end

      # Step 1 — initial recent_in_session(50) reveals msgs 51-100 (descending).
      first_page = MessageStore.recent_in_session(@session_a, 50)
      assert length(first_page) == 50

      first_uris = Enum.map(first_page, & &1.uri)
      expected_first = written |> Enum.slice(50, 50) |> Enum.reverse() |> Enum.map(& &1.uri)
      assert first_uris == expected_first

      # Step 2 — cursor is the oldest visible (msg-51's inserted_at).
      oldest_visible = List.last(first_page)
      assert oldest_visible.body["text"] == "msg-51"

      # Step 3 — older_than(cursor, 50) reveals msgs 1-50 (descending order).
      second_page = MessageStore.older_than(@session_a, oldest_visible.inserted_at, 50)
      assert length(second_page) == 50

      second_uris = Enum.map(second_page, & &1.uri)
      expected_second = written |> Enum.take(50) |> Enum.reverse() |> Enum.map(& &1.uri)
      assert second_uris == expected_second

      # Step 4 — no overlap between pages (invariant: each message appears once).
      assert MapSet.disjoint?(MapSet.new(first_uris), MapSet.new(second_uris))

      # Step 5 — paging past the start returns []; cursor stays harmless.
      oldest_of_all = List.last(second_page)
      assert oldest_of_all.body["text"] == "msg-1"
      assert MessageStore.older_than(@session_a, oldest_of_all.inserted_at, 50) == []
    end

    test "scoped to session — doesn't bleed across sessions" do
      base = ~U[2026-05-17 11:00:00.000000Z]

      for i <- 1..10 do
        insert_msg(@admin, @session_a, "a-#{i}", inserted_at: DateTime.add(base, i, :second))
      end

      for i <- 1..10 do
        insert_msg(@admin, @session_b, "b-#{i}", inserted_at: DateTime.add(base, i, :second))
      end

      cursor = DateTime.add(base, 11, :second)
      result = MessageStore.older_than(@session_a, cursor, 100)

      assert length(result) == 10
      Enum.each(result, fn m -> assert m.session_uri == @session_a end)
    end
  end

  describe "in_session_since/2" do
    test "returns strictly-after `since`, ascending, scoped to session" do
      t0 = ~U[2026-05-16 10:00:00.000000Z]
      t1 = ~U[2026-05-16 10:05:00.000000Z]
      t2 = ~U[2026-05-16 10:10:00.000000Z]
      t3 = ~U[2026-05-16 10:15:00.000000Z]

      _at_t0 = insert_msg(@admin, @session_a, "at-t0", inserted_at: t0)
      at_t1 = insert_msg(@admin, @session_a, "at-t1", inserted_at: t1)
      at_t2 = insert_msg(@bot, @session_a, "at-t2", inserted_at: t2)
      at_t3 = insert_msg(@admin, @session_a, "at-t3", inserted_at: t3)
      _other_session = insert_msg(@admin, @session_b, "other", inserted_at: t2)

      # since = t1 → must EXCLUDE at_t1 (strict-after), include t2, t3.
      result = MessageStore.in_session_since(@session_a, t1)
      uris = Enum.map(result, & &1.uri)
      assert uris == [at_t2.uri, at_t3.uri]

      # since = t0 → includes everything after t0 (t1/t2/t3) in session_a.
      result_t0 = MessageStore.in_session_since(@session_a, t0)
      assert Enum.map(result_t0, & &1.uri) == [at_t1.uri, at_t2.uri, at_t3.uri]
    end

    test "empty result when nothing newer than since" do
      msg = insert_msg(@admin, @session_a, "only-one")
      # Use msg's own inserted_at as the since → strict-after must exclude self
      assert MessageStore.in_session_since(@session_a, msg.inserted_at) == []
    end
  end
end
