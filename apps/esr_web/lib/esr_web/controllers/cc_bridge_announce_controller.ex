defmodule EsrWeb.CcBridgeAnnounceController do
  @moduledoc """
  v1_prototype bridge announce/disconnect/reply/SSE endpoints.

  ## POST /api/cc-bridge/announce

  Body: `{"bridge_id": "...", "agent_uri": "agent://...", "claude_info": {...}, "tools": [...]}`

  - Records the bridge as connected via `Esr.Bridge.V1Prototype.Server.register/2`
  - If `agent_uri` is supplied (Phase 2 path — `ESR_AGENT_URI` env in
    `cc-bridge-attach.sh`): spawns an `Esr.Entity.Agent` Kind at that
    URI under `EsrPluginChat.AgentSupervisor`, binds it to bridge_id
    on the Server, and joins it to `session://main`.
  - If `agent_uri` is absent (legacy / Phase 1 mode): bare bridge
    registration only; no Agent Kind, no Chat routing.

  Responses:
  - 200 `{ok: true, bridge_id}` — normal path (with or without agent)
  - 409 `{ok: false, ..., error: "agent_uri already in use"}` — another
    bridge already holds this agent URI in KindRegistry
  - 422 `{ok: false, ..., error: <reason>}` — Agent spawn failed for
    other reasons (malformed URI, etc)

  ## Phase 5 replacement

  Phase 5's esr_plugin_cc_channel will use a Phoenix Channel /
  WebSocket join handshake instead of HTTP POST, with full CapBAC +
  session binding. This endpoint disappears entirely in Phase 5.
  """

  use Phoenix.Controller, formats: [:json]

  alias Esr.Bridge.V1Prototype.Server, as: BridgeServer
  alias Esr.Entity.{Agent, Session, User}

  def announce(conn, params) do
    bridge_id = params["bridge_id"] || generated_fallback_id()

    info =
      %{
        claude_info: Map.get(params, "claude_info", %{}),
        tools: Map.get(params, "tools", []),
        remote_ip: format_remote_ip(conn.remote_ip)
      }

    :ok = BridgeServer.register(bridge_id, info)

    case spawn_and_bind_agent(params["agent_uri"], bridge_id) do
      :ok ->
        json(conn, %{ok: true, bridge_id: bridge_id})

      {:legacy, :no_agent_uri} ->
        json(conn, %{ok: true, bridge_id: bridge_id})

      {:error, {:already_registered, _}} ->
        conn
        |> put_status(:conflict)
        |> json(%{ok: false, bridge_id: bridge_id, error: "agent_uri already in use"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, bridge_id: bridge_id, error: inspect(reason)})
    end
  end

  defp spawn_and_bind_agent(nil, _bridge_id), do: {:legacy, :no_agent_uri}
  defp spawn_and_bind_agent("", _bridge_id), do: {:legacy, :no_agent_uri}

  defp spawn_and_bind_agent(agent_uri_str, bridge_id) when is_binary(agent_uri_str) do
    with {:ok, agent_uri} <- URI.new(agent_uri_str),
         {:ok, agent_pid} <- start_agent_kind(agent_uri) do
      :ok = BridgeServer.bind_agent(bridge_id, agent_uri, agent_pid)
      :ok = join_agent_to_default_session(agent_uri)
      :ok
    else
      {:error, _} = err -> err
    end
  end

  defp start_agent_kind(agent_uri) do
    spec = {Esr.Kind.Server, {Agent, %{uri: agent_uri}}}

    case DynamicSupervisor.start_child(EsrPluginChat.AgentSupervisor, spec) do
      {:ok, pid} ->
        {:ok, pid}

      # Reconnect: same agent_uri came back, supervisor already has child.
      {:error, {:already_started, pid}} ->
        {:ok, pid}

      # Kind.Server init crashes on KindRegistry conflict — surface as 409.
      {:error, {:already_registered, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_agent_to_default_session(agent_uri) do
    target = URI.new!("#{URI.to_string(Session.default_uri())}/behavior/chat/join")

    _ =
      Esr.Invocation.dispatch(%Esr.Invocation{
        target: target,
        mode: :cast,
        args: %{member: agent_uri},
        ctx: %{
          caller: agent_uri,
          caps: User.admin_caps(),
          reply: :ignore
        }
      })

    :ok
  end

  def disconnect(conn, %{"bridge_id" => bridge_id}) do
    # Unbind Agent first so subsequent reply traffic gets :no_agent
    # rather than racing the terminate.
    case BridgeServer.unbind_agent(bridge_id) do
      {:ok, nil} -> :ok
      {:ok, %URI{} = agent_uri} -> leave_and_terminate_agent(agent_uri)
    end

    :ok = BridgeServer.unregister(bridge_id)
    json(conn, %{ok: true, bridge_id: bridge_id})
  end

  defp leave_and_terminate_agent(agent_uri) do
    target = URI.new!("#{URI.to_string(Session.default_uri())}/behavior/chat/leave")

    _ =
      Esr.Invocation.dispatch(%Esr.Invocation{
        target: target,
        mode: :cast,
        args: %{member: agent_uri},
        ctx: %{
          caller: agent_uri,
          caps: User.admin_caps(),
          reply: :ignore
        }
      })

    case Esr.KindRegistry.lookup(agent_uri) do
      {:ok, agent_pid} ->
        _ = DynamicSupervisor.terminate_child(EsrPluginChat.AgentSupervisor, agent_pid)
        :ok

      :error ->
        :ok
    end
  end

  @doc """
  SSE endpoint the Python bridge subscribes to. Subscribes to the
  per-bridge to_claude Phoenix.PubSub topic and streams each
  `{:to_claude, %{content, meta}}` event as one SSE `data:` block.

  Holds the connection open indefinitely. The bridge process closes
  the connection when claude exits (stdin EOF triggers process exit
  triggers SSE socket close).
  """
  def events_sse(conn, %{"bridge_id" => bridge_id}) do
    :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, "esr:bridge_v1:to_claude:#{bridge_id}")

    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)

    # Initial keep-alive comment so curl shows something immediately
    # and proxies don't close the idle connection.
    {:ok, conn} = Plug.Conn.chunk(conn, ": connected\n\n")

    sse_loop(conn)
  end

  defp sse_loop(conn) do
    receive do
      {:to_claude, payload} ->
        line = "data: " <> Jason.encode!(payload) <> "\n\n"

        case Plug.Conn.chunk(conn, line) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    after
      30_000 ->
        # Keepalive comment to detect dead sockets.
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  @doc """
  Python bridge POSTs here when claude calls its `reply` tool.

  Phase 2c: if the bridge has an Agent Kind bound, forward the text to
  it via `BridgeServer.forward_reply_to_agent/2` — the Agent's
  `handle_kind_message({:reply_received, _}, ...)` in
  `Esr.Behavior.Chat` then constructs the Message + dispatches
  `chat/send` so the reply flows through the same router path as any
  other chat message.

  Legacy fallback (no Agent bound): returns 422. The Phase 1
  `record_reply` path is removed — bridges that want their replies
  visible must announce with `agent_uri`.
  """
  def reply(conn, %{"bridge_id" => bridge_id, "text" => text})
      when is_binary(bridge_id) and is_binary(text) do
    case BridgeServer.forward_reply_to_agent(bridge_id, text) do
      :ok ->
        json(conn, %{ok: true})

      {:error, :no_agent} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "bridge has no agent bound; announce with agent_uri"})
    end
  end

  defp generated_fallback_id do
    "bridge-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp format_remote_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_remote_ip(other), do: inspect(other)
end
