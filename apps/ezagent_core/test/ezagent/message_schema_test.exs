defmodule Ezagent.MessageSchemaTest do
  @moduledoc """
  Phase 2 2a-step 2: integration tests for Ezagent.Message as Ecto.Schema.

  Tests Repo.insert + Repo.get round-trip preserves all struct fields,
  including custom URI type encoding/decoding and {:array, Ezagent.Ecto.URI}
  for mentions.
  """

  # Non-async because Repo state is shared via Sandbox.
  use ExUnit.Case
  alias Ezagent.Message
  alias EzagentCore.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "insert + get round-trip preserves all 7 fields" do
    sender = URI.new!("entity://user/admin")
    session = URI.new!("session://main")
    mention = URI.new!("entity://agent/test_cc-builder")
    ref_uri = URI.new!("message://aabbccdd00000000")
    fixed_at = ~U[2026-05-16 07:00:00.000000Z]

    msg =
      Message.new(sender, %{text: "schema round-trip", attachments: []},
        mentions: [mention],
        ref: ref_uri,
        inserted_at: fixed_at
      )

    # session_uri set at MessageStore.write boundary (caller-supplied);
    # for this test we set it directly.
    msg_with_session = %{msg | session_uri: session}

    {:ok, _inserted} = Repo.insert(msg_with_session)
    loaded = Repo.get(Message, msg.uri)

    assert loaded.uri == msg.uri
    assert loaded.session_uri == session
    assert loaded.sender == sender
    assert loaded.mentions == [mention]
    assert loaded.body == %{"text" => "schema round-trip", "attachments" => []}
    # body comes back with string keys because it's a generic :map column;
    # callers handle either form depending on consumer (LV uses string keys).
    assert loaded.ref == ref_uri
    assert DateTime.compare(loaded.inserted_at, fixed_at) == :eq
  end

  test "insert with empty mentions list" do
    sender = URI.new!("entity://user/admin")
    session = URI.new!("session://main")

    msg = Message.new(sender, %{text: "no mentions", attachments: []})
    msg_with_session = %{msg | session_uri: session}

    {:ok, _} = Repo.insert(msg_with_session)
    loaded = Repo.get(Message, msg.uri)

    assert loaded.mentions == []
  end

  test "insert with nil ref" do
    sender = URI.new!("entity://agent/test_cc-builder")
    session = URI.new!("session://main")

    msg = Message.new(sender, %{text: "no reply", attachments: []})
    msg_with_session = %{msg | session_uri: session}

    {:ok, _} = Repo.insert(msg_with_session)
    loaded = Repo.get(Message, msg.uri)

    assert loaded.ref == nil
  end
end
