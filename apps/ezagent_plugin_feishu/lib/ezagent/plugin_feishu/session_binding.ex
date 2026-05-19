defmodule EzagentPluginFeishu.SessionBinding do
  @moduledoc """
  PR #144 SPEC v2 §5.8 — Feishu chat_id ↔ ESR session_uri binding store.

  **Pure data module.** Symmetric to `EzagentPluginFeishu.UserBinding`
  (open_id ↔ user_uri). Read by `EzagentPluginFeishu.InboundDispatcher`
  (chat_id → session) and by `EzagentPluginFeishu.Behavior.FeishuOutbound`
  (session → chat_id, for outbound mirror).

  ## Why a join table replaces the prior routing rule

  Pre-PR-144, the binding was implicit: `Ezagent.Template.FeishuChatBinding`
  added a row to `MentionRouting` with matcher
  `in_session(session_uri) → [feishu://oc_xxx]`. This worked because
  `feishu://oc_xxx` was a Receiver Kind that owned the Feishu API call.

  Per §5.8, plugins MUST NOT own a top-level scheme. With
  `feishu://` deleted, the binding has to become a first-class data
  shape independent of routing rules — hence this module + the
  `feishu_session_bindings` table.

  ## Cardinality

  One chat_id maps to exactly one session (PK on chat_id). The
  reverse direction (one session → chat_id) currently returns at
  most one row but is a list-returning query so a future "fan one
  session to multiple chats" addition is backwards-compatible.
  """

  use Ecto.Schema
  import Ecto.Query

  alias EzagentCore.Repo

  @primary_key {:chat_id, :string, autogenerate: false}
  schema "feishu_session_bindings" do
    field :session_uri, :string
    field :enabled, :boolean, default: true
    field :created_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          chat_id: String.t(),
          session_uri: String.t(),
          enabled: boolean(),
          created_at: DateTime.t()
        }

  @doc """
  Bind `chat_id` (Feishu side) to `session_uri` (ESR side).

  Upserts on chat_id — re-binding silently replaces the prior
  session_uri. `enabled` defaults to true.
  """
  @spec bind(String.t(), URI.t() | String.t()) :: {:ok, t()} | {:error, term()}
  def bind(chat_id, session_uri)
      when is_binary(chat_id) and chat_id != "" do
    row = %__MODULE__{
      chat_id: chat_id,
      session_uri: to_str(session_uri),
      enabled: true,
      created_at: DateTime.utc_now()
    }

    Repo.insert(row,
      on_conflict: {:replace_all_except, [:chat_id, :created_at]},
      conflict_target: :chat_id,
      returning: true
    )
  end

  @doc "Remove a binding. Returns :ok or {:error, :not_found}."
  @spec unbind(String.t()) :: :ok | {:error, :not_found}
  def unbind(chat_id) when is_binary(chat_id) do
    case Repo.get(__MODULE__, chat_id) do
      nil ->
        {:error, :not_found}

      row ->
        Repo.delete(row)
        :ok
    end
  end

  @doc """
  Resolve a Feishu chat_id to its bound session URI.
  Returns `{:ok, URI.t()}` for a bound + enabled chat, `:error` for
  unbound or disabled.
  """
  @spec resolve(String.t()) :: {:ok, URI.t()} | :error
  def resolve(chat_id) when is_binary(chat_id) and chat_id != "" do
    case Repo.get(__MODULE__, chat_id) do
      %__MODULE__{session_uri: uri_str, enabled: true} ->
        {:ok, URI.parse(uri_str)}

      _ ->
        :error
    end
  end

  def resolve(_), do: :error

  @doc """
  Reverse: return all chat_ids currently bound + enabled for
  `session_uri`. Used by `FeishuOutbound` to know whether (and where)
  to mirror an outbound chat send.

  Returns `[]` if no binding. Today this returns at most one entry,
  but the list shape leaves room for one-session-to-many-chats fan-out.
  """
  @spec chat_ids_for(URI.t() | String.t()) :: [String.t()]
  def chat_ids_for(session_uri) do
    uri_str = to_str(session_uri)

    Repo.all(
      from b in __MODULE__,
        where: b.session_uri == ^uri_str and b.enabled == true,
        select: b.chat_id
    )
  end

  @doc "List every binding (admin LV / debug)."
  @spec list_all() :: [t()]
  def list_all do
    Repo.all(from b in __MODULE__, order_by: b.created_at)
  end

  defp to_str(%URI{} = u), do: URI.to_string(u)
  defp to_str(s) when is_binary(s), do: s
end
