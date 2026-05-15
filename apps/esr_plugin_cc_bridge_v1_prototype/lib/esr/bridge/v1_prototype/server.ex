defmodule Esr.Bridge.V1Prototype.Server do
  @moduledoc """
  Connected-bridge state tracker.

  Phase 1 v1_prototype:
  - Claude (NOT this GenServer) spawns the Python MCP bridge subprocess
    via `--mcp-config` mechanism — see `Esr.Bridge.V1Prototype.McpConfigWriter`
  - The bridge calls back to esrd's `POST /api/cc-bridge/announce`
  - That controller calls `register/2` here to record a connected bridge
  - LiveView /admin subscribes to `topic/0` for live connected count

  ## Why no Port.open here anymore

  Earlier prototype tried to have ESR spawn the Python script. That was
  wrong — Claude itself spawns its MCP servers when started with
  `--mcp-config`. Our role is to be the HTTP target the bridge posts
  announcements to.

  ## State shape

  `%{bridges: %{bridge_id => %{connected_at: DateTime, info: map}}}`
  """

  use GenServer

  @bridge_topic "esr:bridge_v1:events"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "PubSub topic for LV subscribers."
  def topic, do: @bridge_topic

  @doc """
  Record a connected bridge. Called by the announce HTTP controller.

  Returns `:ok` and broadcasts `{:cc_connected, bridge_id, info}` on
  the bridge topic.
  """
  @spec register(String.t(), map()) :: :ok
  def register(bridge_id, info) when is_binary(bridge_id) and is_map(info) do
    GenServer.call(__MODULE__, {:register, bridge_id, info})
  end

  @doc "Remove a bridge. Broadcasts `{:cc_disconnected, bridge_id}`."
  @spec unregister(String.t()) :: :ok
  def unregister(bridge_id) when is_binary(bridge_id) do
    GenServer.call(__MODULE__, {:unregister, bridge_id})
  end

  @doc "List all currently connected bridges as `[{bridge_id, info}]`."
  @spec list_connected() :: [{String.t(), map()}]
  def list_connected do
    GenServer.call(__MODULE__, :list_connected)
  end

  @doc "How many bridges are connected? Returns 0 if GenServer not started."
  def count do
    case Process.whereis(__MODULE__) do
      nil -> 0
      _ -> GenServer.call(__MODULE__, :count)
    end
  end

  @doc "Legacy callsite from the LiveView — :down / :ready / count summary."
  def status do
    case Process.whereis(__MODULE__) do
      nil ->
        :down

      _ ->
        case count() do
          0 -> :no_bridges
          n -> {:connected, n}
        end
    end
  end

  # --- callbacks --------------------------------------------------------

  @impl true
  def init(_) do
    {:ok, %{bridges: %{}}}
  end

  @impl true
  def handle_call({:register, bridge_id, info}, _from, state) do
    entry = %{connected_at: DateTime.utc_now(), info: info}
    bridges = Map.put(state.bridges, bridge_id, entry)

    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      @bridge_topic,
      {:cc_connected, bridge_id, entry}
    )

    {:reply, :ok, %{state | bridges: bridges}}
  end

  def handle_call({:unregister, bridge_id}, _from, state) do
    bridges = Map.delete(state.bridges, bridge_id)

    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      @bridge_topic,
      {:cc_disconnected, bridge_id}
    )

    {:reply, :ok, %{state | bridges: bridges}}
  end

  def handle_call(:list_connected, _from, state) do
    list = Map.to_list(state.bridges)
    {:reply, list, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.bridges), state}
  end
end
