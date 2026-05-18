defmodule EsrPluginCcChannel.BridgeRegistry do
  @moduledoc """
  `agent_uri → channel_pid` lookup table for v2 CC bridges, plus the
  observability surface the admin LV needs (connect count, connected
  list with metadata, PubSub events on bind/unbind).

  The Channel pid IS the bridge identity — Phoenix gives us one pid per
  joined topic, so we don't carry a separate bridge_id like v1 did.

  ETS-backed, declared in `EsrPluginCcChannel.Application.start/2`.

  ## Storage shape (Phase 7 PR 32a)

  Each row is `{agent_uri_string, %{pid: pid(), connected_at: DateTime.t(),
  info: map()}}`. The `info` map carries whatever the Channel captured
  at join time (claude version, tool list, remote ip) so admin LV can
  render a useful row per bridge without round-tripping to the
  Channel.

  ## PubSub events

  On bind/unbind, broadcasts on `topic/0` (`"esr:cc_channel:bridges"`)
  the events `{:cc_connected, agent_uri, info}` and
  `{:cc_disconnected, agent_uri}`. Admin LV subscribes at mount to
  keep its connected-count live.
  """

  @table :esr_plugin_cc_channel_bridges
  @pubsub EsrCore.PubSub
  @topic "esr:cc_channel:bridges"

  @doc "ETS table init — called from Application.start/2."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "PubSub topic for connect/disconnect events. Stable identifier."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc """
  Bind `agent_uri` to the Channel pid with optional metadata.

  Idempotent if same pid; returns `{:error, :already_bound}` if a
  different live pid already holds the URI (Phoenix would normally
  reject the second join via `:already_started`, this just surfaces
  it consistently).

  Broadcasts `{:cc_connected, agent_uri, info}` on `topic/0`.
  """
  @spec bind(URI.t(), pid(), map()) :: :ok | {:error, term()}
  def bind(%URI{} = agent_uri, channel_pid, info \\ %{}) when is_pid(channel_pid) and is_map(info) do
    key = URI.to_string(agent_uri)
    row = %{pid: channel_pid, connected_at: DateTime.utc_now(), info: info}

    case :ets.lookup(@table, key) do
      [{^key, %{pid: existing_pid}}] when existing_pid == channel_pid ->
        :ok

      [{^key, %{pid: existing_pid}}] ->
        if Process.alive?(existing_pid) do
          {:error, :already_bound}
        else
          true = :ets.insert(@table, {key, row})
          broadcast_connected(agent_uri, info)
          :ok
        end

      [] ->
        true = :ets.insert(@table, {key, row})
        broadcast_connected(agent_uri, info)
        :ok
    end
  end

  @doc "Unbind `agent_uri`. Broadcasts `{:cc_disconnected, agent_uri}`."
  @spec unbind(URI.t()) :: :ok
  def unbind(%URI{} = agent_uri) do
    key = URI.to_string(agent_uri)
    existed? = :ets.member(@table, key)
    :ets.delete(@table, key)
    if existed?, do: broadcast_disconnected(agent_uri)
    :ok
  end

  @doc """
  Look up the Channel pid bound to `agent_uri`.

  Returns `{:ok, pid}` for the live bridge; `:error` if unbound.
  """
  @spec lookup(URI.t()) :: {:ok, pid()} | :error
  def lookup(%URI{} = agent_uri) do
    case :ets.lookup(@table, URI.to_string(agent_uri)) do
      [{_, %{pid: pid}}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  List every bound bridge as `[{agent_uri, pid}]` — back-compat shape.

  Prefer `list_connected/0` for admin UI: it carries `connected_at`
  + `info` for each row.
  """
  @spec list_all() :: [{URI.t(), pid()}]
  def list_all do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {key, %{pid: pid}} -> {URI.parse(key), pid} end)
  end

  @doc """
  List every bound bridge with metadata:
  `[{agent_uri :: URI.t(), %{pid: pid(), connected_at: DateTime.t(), info: map()}}]`.
  """
  @spec list_connected() :: [{URI.t(), map()}]
  def list_connected do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {key, row} -> {URI.parse(key), row} end)
  end

  @doc "Number of currently bound bridges."
  @spec count() :: non_neg_integer()
  def count, do: :ets.info(@table, :size) || 0

  @doc """
  High-level status atom for admin summary panels.

    * `:no_bridges` — table is empty
    * `{:connected, n}` — n ≥ 1 bridges bound
  """
  @spec status() :: :no_bridges | {:connected, pos_integer()}
  def status do
    case count() do
      0 -> :no_bridges
      n -> {:connected, n}
    end
  end

  defp broadcast_connected(agent_uri, info) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:cc_connected, agent_uri, info})
  end

  defp broadcast_disconnected(agent_uri) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:cc_disconnected, agent_uri})
  end
end
