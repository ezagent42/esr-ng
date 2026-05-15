defmodule Esr.Behavior.Chat do
  @moduledoc """
  Chat Behavior — Decision P2-D2 K-path: 4 actions, registered per-Kind
  subset to realize Decision #61 "ESR is router not req/resp app".

  ## Action / Kind matrix

      | action    | registered on Kind(s)                  | mode  |
      |-----------|----------------------------------------|-------|
      | :send     | Esr.Entity.Session                     | cast  |
      | :join     | Esr.Entity.Session                     | call  |
      | :leave    | Esr.Entity.Session                     | cast  |
      | :receive  | Esr.Entity.User, Esr.Entity.Agent      | cast  |

  Session-side actions (`:send / :join / :leave`) mutate the Session's
  `:chat` slice (members map / monitors / last_seen). When `:send`
  resolves the recipient list, it dispatches `:receive` on each
  member's URI — the inbound side runs against User/Agent's own
  `:chat` slice (Phase 2b: just delivers via `Phoenix.PubSub` broadcast
  + LV stream insert; per ARCHITECTURE §10.4 no inbox state on the
  receiver in Phase 2).

  ## Why one Behavior across Kinds

  Per Decision P2-D2 K-path: avoiding two Behaviors (ChatSession +
  ChatMember) keeps the protocol contract in one place. The dispatch
  fan-out (Session dispatches to N receivers) is the natural router
  pattern — single Behavior with multiple actions, registered to the
  Kinds that consume them.

  ## Phase 2a stub

  All `invoke/4` clauses return `{:error, :not_implemented_in_2a}`.
  The contract is what matters for 2a — interface schemas + action
  list — so that 2b can fill the bodies against a fixed contract
  without touching Behavior.Chat's public surface.
  """

  @behaviour Esr.Behavior

  @impl Esr.Behavior
  def actions, do: [:send, :receive, :join, :leave]

  @impl Esr.Behavior
  def state_slice, do: :chat

  @impl Esr.Behavior
  def init_slice(_args) do
    # 2b fills shape per-Kind:
    # - Session: %{members: %{}, monitors: %{}, last_seen: %{}}
    # - User/Agent: %{} (no inbox state — broadcast-only)
    %{}
  end

  # All clauses stub in 2a — bodies land in 2b. Per memory
  # `feedback_let_it_crash_no_workarounds`: return a typed error
  # rather than a default-value or partial-state placeholder.

  @impl Esr.Behavior
  def invoke(:send, _slice, _args, _ctx), do: {:error, :not_implemented_in_2a}
  def invoke(:receive, _slice, _args, _ctx), do: {:error, :not_implemented_in_2a}
  def invoke(:join, _slice, _args, _ctx), do: {:error, :not_implemented_in_2a}
  def invoke(:leave, _slice, _args, _ctx), do: {:error, :not_implemented_in_2a}

  @impl Esr.Behavior
  def interface do
    %{
      send: %{
        args: %{message: message_schema()},
        returns: %{stored: :boolean},
        modes: [:cast]
      },
      receive: %{
        args: %{message: message_schema()},
        returns: %{},
        modes: [:cast]
      },
      join: %{
        args: %{member: :uri},
        returns: %{members: {:list, :uri}},
        modes: [:call]
      },
      leave: %{
        args: %{member: :uri},
        returns: %{},
        modes: [:cast]
      }
    }
  end

  # Nested record shape for `%Esr.Message{}` envelope — uses :uri primitive
  # (added to InterfaceValidator in this same step) so identity fields are
  # typed URIs at the contract layer, matching the in-memory representation.
  # `body` stays :map because the body sub-shape (text + attachments) is
  # better validated by callers that know the body content type — Phase 2
  # only handles text-chat, Phase 5 expands attachments.
  defp message_schema do
    %{
      uri: :string,
      sender: :uri,
      mentions: {:list, :uri},
      body: :map,
      ref: {:option, :uri},
      inserted_at: :map
    }
  end
end
