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

  @doc "PubSub topic for LV bridge-connected/disconnected events."
  def topic, do: @bridge_topic

  @doc """
  Per-bridge inbound topic. SSE endpoint subscribes, gets events
  destined for claude over this bridge.
  """
  def to_claude_topic(bridge_id), do: "esr:bridge_v1:to_claude:#{bridge_id}"

  @doc """
  Per-bridge replies topic. LV subscribes to render claude's reply tool
  calls in real time.
  """
  def replies_topic(bridge_id), do: "esr:bridge_v1:replies:#{bridge_id}"

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

  @doc """
  Push a message to claude via the named bridge.

  Broadcasts on the per-bridge inbound topic; the SSE endpoint
  subscribed to that topic streams the event to the Python bridge,
  which converts to an MCP `notifications/claude/channel` so claude
  sees a `<channel>` tag.

  `content` is the body string; `meta` is a string→string map that
  becomes attributes on the `<channel>` tag.
  """
  @spec push_to_claude(String.t(), String.t(), map()) :: :ok
  def push_to_claude(bridge_id, content, meta \\ %{})
      when is_binary(bridge_id) and is_binary(content) and is_map(meta) do
    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      to_claude_topic(bridge_id),
      {:to_claude, %{content: content, meta: meta}}
    )

    :ok
  end

  @doc """
  Record a reply from claude (via the reply tool POST). Stores the
  most recent N replies per bridge in the GenServer state and
  broadcasts on the per-bridge replies topic.
  """
  @spec record_reply(String.t(), String.t()) :: :ok
  def record_reply(bridge_id, text) when is_binary(bridge_id) and is_binary(text) do
    GenServer.call(__MODULE__, {:record_reply, bridge_id, text})
  end

  @doc "List recent replies for a bridge (most recent first), max 20."
  @spec recent_replies(String.t()) :: [%{at: DateTime.t(), text: String.t()}]
  def recent_replies(bridge_id) when is_binary(bridge_id) do
    GenServer.call(__MODULE__, {:recent_replies, bridge_id})
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
    {:ok, %{bridges: %{}, replies: %{}}}
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

  def handle_call({:record_reply, bridge_id, text}, _from, state) do
    entry = %{at: DateTime.utc_now(), text: text}
    prior = Map.get(state.replies, bridge_id, [])
    # Most recent first, cap at 20.
    new_list = [entry | prior] |> Enum.take(20)
    new_replies = Map.put(state.replies, bridge_id, new_list)

    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      replies_topic(bridge_id),
      {:claude_reply, bridge_id, entry}
    )

    {:reply, :ok, %{state | replies: new_replies}}
  end

  def handle_call({:recent_replies, bridge_id}, _from, state) do
    {:reply, Map.get(state.replies, bridge_id, []), state}
  end
end
