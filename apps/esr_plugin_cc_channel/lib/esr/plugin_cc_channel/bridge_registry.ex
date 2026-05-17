defmodule EsrPluginCcChannel.BridgeRegistry do
  @moduledoc """
  Phase 6 PR 4 — `agent_uri → channel_pid` lookup table for v2 CC
  bridges.

  Owns the inverse of the v1_prototype Server's `agent_uri → bridge_id`
  + `bridge_id → pid` map. v2 collapses to one hop because the
  Channel pid IS the bridge identity (Phoenix gives us a pid per
  joined topic).

  ETS-backed, declared in EsrPluginCcChannel.Application start.
  Single-writer (the Channel itself on join + terminate); :public so
  external lookups don't have to round-trip the owner.
  """

  @table :esr_plugin_cc_channel_bridges

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @spec bind(URI.t(), pid()) :: :ok | {:error, term()}
  def bind(%URI{} = agent_uri, channel_pid) when is_pid(channel_pid) do
    key = URI.to_string(agent_uri)

    case :ets.lookup(@table, key) do
      [{^key, existing_pid}] when existing_pid == channel_pid ->
        :ok

      [{^key, existing_pid}] ->
        if Process.alive?(existing_pid) do
          {:error, :already_bound}
        else
          true = :ets.insert(@table, {key, channel_pid})
          :ok
        end

      [] ->
        true = :ets.insert(@table, {key, channel_pid})
        :ok
    end
  end

  @spec unbind(URI.t()) :: :ok
  def unbind(%URI{} = agent_uri) do
    :ets.delete(@table, URI.to_string(agent_uri))
    :ok
  end

  @spec lookup(URI.t()) :: {:ok, pid()} | :error
  def lookup(%URI{} = agent_uri) do
    case :ets.lookup(@table, URI.to_string(agent_uri)) do
      [{_, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @spec list_all() :: [{URI.t(), pid()}]
  def list_all do
    :ets.tab2list(@table)
    |> Enum.map(fn {key, pid} -> {URI.parse(key), pid} end)
  end
end
