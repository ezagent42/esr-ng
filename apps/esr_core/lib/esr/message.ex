defmodule Esr.Message do
  @moduledoc """
  Message — Entity ↔ Entity 通信的 envelope。

  Per ARCHITECTURE §3.5 + Decision #39 + #40:Message 是 `%Esr.Invocation{}` 的
  特化 args shape,**identity invariant 不可变** —  sender / mentions / body /
  ref / inserted_at 跨任意层 routing/forwarding 不变;中转者只创建携带 Message
  的新 Invocation,从不修改 Message 本身。

  ## Phase 2 shape(P2-D1 决策)

      uri:         "message://<uuid16>"  # identity reference,by new/3 auto-gen
      sender:      %URI{}                # 谁创建(`user://...` / `agent://...`)
      mentions:    [%URI{}]              # @-targets
      body:        %{text: String.t(), attachments: [%URI{}]}  # 结构化
      ref:         %URI{} | nil          # ^reply-to 另一条 message URI
      inserted_at: DateTime.t()

  `uri` 是 6th 字段,作为 identity reference;identity invariant 仍只锁原 5
  字段(per Decision #40)。`uri` 由 `new/3` 在构造时 UUID 生成,支持 in-flight
  ref 引用(reply 路径无需等 persist 才有 URI)。

  ## API

      Esr.Message.new(sender, body, opts \\\\ [])

  必填 positional:`sender`(URI)+ `body`(map);其余 opts:
  - `:mentions` — `[URI.t()]`,默认 `[]`
  - `:ref` — `URI.t()` 或 `nil`,默认 `nil`
  - `:inserted_at` — `DateTime.t()`,默认 `DateTime.utc_now()`
  - `:uri` — 重写 URI(测试 / replay 用,正常不传)

  ## Phase 2 边界

  - `body.attachments` 字段保留(per §10.5 G 设计预留)但 Phase 2 永远 `[]`;
    Phase 5 attachments 接入再用
  - `Jason.Encoder` impl 把 `%URI{}` stringify(否则默认 encoder 把 URI struct
    当 generic struct 序列化所有字段,wire 上膨胀)
  """

  use Ecto.Schema

  # Drop Ecto.Schema's `:__meta__` field from JSON serialization (it's
  # internal Ecto state, not part of the Message envelope on the wire).
  @derive {Jason.Encoder, except: [:__meta__]}

  @type body_shape :: %{
          required(:text) => String.t(),
          required(:attachments) => [URI.t()]
        }

  @type t :: %__MODULE__{
          uri: String.t(),
          session_uri: URI.t() | nil,
          sender: URI.t(),
          mentions: [URI.t()],
          body: body_shape(),
          ref: URI.t() | nil,
          inserted_at: DateTime.t()
        }

  # `uri` is the primary key (message://<uuid16>); ecto_sqlite3 stores it
  # as TEXT. Disable Ecto's default :id primary key.
  @primary_key false

  schema "messages" do
    field :uri, :string, primary_key: true
    # session_uri is routing metadata (not part of identity invariant per
    # §3.5); caller supplies at MessageStore.write/2 boundary.
    field :session_uri, Esr.Ecto.URI
    field :sender, Esr.Ecto.URI
    # mentions stored as JSON array of strings (each URI dumped via
    # Esr.Ecto.URI.dump → string). ecto_sqlite3 JSON-encodes arrays
    # transparently.
    field :mentions, {:array, Esr.Ecto.URI}, default: []
    # body is a JSON-encoded map per ecto_sqlite3's :map column handling.
    field :body, :map
    field :ref, Esr.Ecto.URI
    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Construct a new Message.

  Auto-generates `uri` via 8 random bytes (16 hex chars) → `"message://<hex>"`.
  Caller can override via `:uri` opt for tests / message replay scenarios.
  """
  @spec new(URI.t(), body_shape(), keyword()) :: t()
  def new(%URI{} = sender, %{text: text} = body, opts \\ []) when is_binary(text) do
    %__MODULE__{
      uri: Keyword.get(opts, :uri, generate_uri()),
      sender: sender,
      mentions: Keyword.get(opts, :mentions, []),
      body: Map.put_new(body, :attachments, []),
      ref: Keyword.get(opts, :ref),
      inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
    }
  end

  defp generate_uri do
    "message://" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end

# Jason encoder for `%URI{}` — stringify on the wire instead of dumping struct
# fields. Required so Message + body + mentions serialize cleanly to JSON
# (e.g., LV PubSub payloads, SSE bridge events). Defined here in esr_core
# (the package that introduces URI as a first-class data type for messages).
defimpl Jason.Encoder, for: URI do
  def encode(uri, opts) do
    Jason.Encode.string(URI.to_string(uri), opts)
  end
end

# Note: `%Esr.Message{}` JSON encoding is via `@derive {Jason.Encoder,
# except: [:__meta__]}` at the schema declaration (see top of module).
# That handles `:__meta__` (Ecto's internal field) cleanly. No manual
# defimpl needed.
