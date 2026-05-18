defmodule Ezagent.Bridge.V1Prototype.Server do
  @moduledoc """
  Connected-bridge state tracker.

  Phase 1 v1_prototype:
  - Claude (NOT this GenServer) spawns the Python MCP bridge subprocess
    via `--mcp-config` mechanism — see `Ezagent.Bridge.V1Prototype.McpConfigWriter`
  - The bridge calls back to esrd's `POST /api/cc-bridge/announce`
  - That controller calls `register/2` here to record a connected bridge
  - LiveView /admin subscribes to `topic/0` for live connected count

  ## Why no Port.open here anymore

  Earlier prototype tried to have ESR spawn the Python script. That was
  wrong — Claude itself spawns its MCP servers when started with
  `--mcp-config`. Our role is to be the HTTP target the bridge posts
  announcements to.

  ## State shape

  `%{bridges: %{bridge_id => %{connected_at: DateTime, info: map}},
     replies: %{bridge_id => [%{at, text}]},
     bridge_to_agent: %{bridge_id => agent_pid},
     agent_to_bridge: %{agent_uri_string => bridge_id}}`

  Phase 2c-step 1 added the bridge↔agent dual map: when a bridge
  announces with an `agent_uri`, the controller spawns an
  `Ezagent.Entity.Agent` Kind at that URI and registers the binding here.
  Reply traffic from claude (POST /reply) then routes through the
  Agent Kind via `forward_reply_to_agent/2`, which in turn dispatches
  a `chat/send` on `session://main` so the message lands on every
  member's `:receive` path (including admin via LV).
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
      EzagentCore.PubSub,
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

  # --- Phase 2c bridge↔agent binding ------------------------------------

  @doc """
  Bind `bridge_id` to a running `Ezagent.Entity.Agent` pid + its URI.

  Called from the announce controller AFTER the controller spawns the
  Agent Kind via `DynamicSupervisor.start_child`. Idempotent — re-binding
  a bridge to the same agent_uri overwrites silently (handles bridge
  reconnect).
  """
  @spec bind_agent(String.t(), URI.t(), pid()) :: :ok
  def bind_agent(bridge_id, %URI{} = agent_uri, agent_pid)
      when is_binary(bridge_id) and is_pid(agent_pid) do
    GenServer.call(__MODULE__, {:bind_agent, bridge_id, agent_uri, agent_pid})
  end

  @doc """
  Forward a claude reply to the Agent Kind bound to `bridge_id`.

  Phase 3c-step 2 (P3-D8 contract):
  - `session_uris` is a list of target session URIs (Phase 3 multi-session)
  - `ref` is an optional message URI being replied to (for consistency check)

  Agent Kind's `handle_kind_message({:reply_received, session_uris, text, ref}, ...)`
  dispatches `chat/send` once per session_uri (envelope reused per
  identity invariant Decision #40).

  Returns `{:error, :no_agent}` if no Agent is bound.
  """
  @spec forward_reply_to_agent(String.t(), [String.t()], String.t(), String.t() | nil) ::
          :ok | {:error, :no_agent}
  def forward_reply_to_agent(bridge_id, session_uris, text, ref \\ nil)
      when is_binary(bridge_id) and is_list(session_uris) and is_binary(text) do
    forward_reply_to_agent(bridge_id, session_uris, text, ref, [])
  end

  @doc """
  Phase 6 PR 14: reply with attachments. `attachments` is a list of
  `%{"type" => "image" | "file", "local_path" => "/abs", "name" => "x"}`
  maps. Sent to Agent Kind as
  `{:reply_received, sessions, text, ref, attachments}`.
  """
  @spec forward_reply_to_agent(String.t(), [String.t()], String.t(), String.t() | nil, [map()]) ::
          :ok | {:error, :no_agent}
  def forward_reply_to_agent(bridge_id, session_uris, text, ref, attachments)
      when is_binary(bridge_id) and is_list(session_uris) and is_binary(text) and
             is_list(attachments) do
    GenServer.call(__MODULE__, {:forward_reply, bridge_id, session_uris, text, ref, attachments})
  end

  @doc "Look up the bridge_id bound to an Agent URI (for outbound to_claude push)."
  @spec bridge_for_agent(URI.t()) :: {:ok, String.t()} | :error
  def bridge_for_agent(%URI{} = agent_uri) do
    GenServer.call(__MODULE__, {:bridge_for_agent, agent_uri})
  end

  @doc """
  Unbind an agent on bridge disconnect. Removes both directions of the
  map. Idempotent.
  """
  @spec unbind_agent(String.t()) :: {:ok, URI.t() | nil}
  def unbind_agent(bridge_id) when is_binary(bridge_id) do
    GenServer.call(__MODULE__, {:unbind_agent, bridge_id})
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
    {:ok,
     %{
       bridges: %{},
       replies: %{},
       bridge_to_agent: %{},
       agent_to_bridge: %{}
     }}
  end

  @impl true
  def handle_call({:register, bridge_id, info}, _from, state) do
    entry = %{connected_at: DateTime.utc_now(), info: info}
    bridges = Map.put(state.bridges, bridge_id, entry)

    Phoenix.PubSub.broadcast(
      EzagentCore.PubSub,
      @bridge_topic,
      {:cc_connected, bridge_id, entry}
    )

    {:reply, :ok, %{state | bridges: bridges}}
  end

  def handle_call({:unregister, bridge_id}, _from, state) do
    bridges = Map.delete(state.bridges, bridge_id)

    Phoenix.PubSub.broadcast(
      EzagentCore.PubSub,
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
      EzagentCore.PubSub,
      replies_topic(bridge_id),
      {:claude_reply, bridge_id, entry}
    )

    {:reply, :ok, %{state | replies: new_replies}}
  end

  def handle_call({:recent_replies, bridge_id}, _from, state) do
    {:reply, Map.get(state.replies, bridge_id, []), state}
  end

  def handle_call({:bind_agent, bridge_id, agent_uri, agent_pid}, _from, state) do
    new_state = %{
      state
      | bridge_to_agent: Map.put(state.bridge_to_agent, bridge_id, agent_pid),
        agent_to_bridge: Map.put(state.agent_to_bridge, URI.to_string(agent_uri), bridge_id)
    }

    {:reply, :ok, new_state}
  end

  # Phase 6 PR 14: old 5-tuple kept for back-compat with any caller
  # that doesn't pass attachments — delegates with empty list.
  def handle_call({:forward_reply, bridge_id, session_uris, text, ref}, from, state) do
    handle_call({:forward_reply, bridge_id, session_uris, text, ref, []}, from, state)
  end

  def handle_call({:forward_reply, bridge_id, session_uris, text, ref, attachments}, _from, state) do
    case Map.get(state.bridge_to_agent, bridge_id) do
      nil ->
        {:reply, {:error, :no_agent}, state}

      agent_pid when is_pid(agent_pid) ->
        # send/2 lands in Ezagent.Kind.Server.handle_info/2 which fans out
        # to each composed Behavior's handle_kind_message/3. Chat's
        # clause for {:reply_received, session_uris, text, ref, attachments}
        # dispatches chat/send per session_uri (envelope reused).
        send(agent_pid, {:reply_received, session_uris, text, ref, attachments})
        {:reply, :ok, state}
    end
  end

  def handle_call({:bridge_for_agent, agent_uri}, _from, state) do
    case Map.get(state.agent_to_bridge, URI.to_string(agent_uri)) do
      nil -> {:reply, :error, state}
      bridge_id -> {:reply, {:ok, bridge_id}, state}
    end
  end

  def handle_call({:unbind_agent, bridge_id}, _from, state) do
    case Map.get(state.bridge_to_agent, bridge_id) do
      nil ->
        {:reply, {:ok, nil}, state}

      _agent_pid ->
        # Find agent_uri so we can remove from agent_to_bridge too.
        {agent_uri_str, agent_to_bridge} =
          Enum.reduce(state.agent_to_bridge, {nil, %{}}, fn
            {uri, ^bridge_id}, {nil, acc} -> {uri, acc}
            {uri, bid}, {found, acc} -> {found, Map.put(acc, uri, bid)}
          end)

        new_state = %{
          state
          | bridge_to_agent: Map.delete(state.bridge_to_agent, bridge_id),
            agent_to_bridge: agent_to_bridge
        }

        agent_uri = if agent_uri_str, do: URI.new!(agent_uri_str)
        {:reply, {:ok, agent_uri}, new_state}
    end
  end
end
