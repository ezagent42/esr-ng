defmodule EzagentPluginLiveview.PtyTerminalLive do
  @moduledoc """
  Phase 5 PR 4: Pty-Web — xterm.js rendering of a live cc-pty TUI in
  the browser.

  ## Architecture (per IMPLEMENTATION_ROADMAP §1.3 #1)

  - Output: PtyServer broadcasts each stdout/stderr chunk to
    `pty:output:<agent_uri>` PubSub. LV subscribes and pushes the
    raw bytes to xterm via `push_event(socket, "pty_chunk", %{bytes})`
  - Input: xterm hook `onData` fires `pushEvent("pty_input", {bytes})`
    → this LV's `handle_event("pty_input", ...)` → `Ezagent.Invocation.dispatch`
    to `entity://agent/<flavor>_<name>?action=pty.write` (CapBAC +
    audit fire) → `Ezagent.Behavior.Pty.invoke(:write, ...)` looks up
    PtyServer for `ctx.self_uri` (the agent URI) and writes the bytes.

    PR #146 (SPEC v2 §5.7) dissolves the `pty-input://default`
    synthetic singleton — the dispatch target IS the agent now.

  **Never pushes input directly to PubSub.** The dispatch path is the
  enforced invariant (`agents_pty_input_dispatch_test.exs`).

  ## URL

  `/identities/agents/:uri/terminal` — `:uri` is URI-encoded `entity://agent/...`
  """

  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  import Phoenix.Component

  @impl true
  def mount(%{"uri" => encoded_uri}, session, socket) do
    case parse_agent_uri(encoded_uri) do
      {:ok, agent_uri} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            EzagentCore.PubSub,
            Ezagent.PluginCc.PtyServer.output_topic(agent_uri)
          )

          # PR #128 — ttyd-style initial render. Two complementary
          # nudges so the operator never sees a black terminal:
          # (1) replay the PtyServer's recent buffer so the LAST
          # ANSI-rendered screen the TUI emitted shows immediately
          # (sufficient for most cases — claude's full screen is
          # almost always within the last 64KB of output);
          # (2) trigger a winsize nudge so the TUI redraws fresh
          # output through the live PubSub path, covering the case
          # where the last redraw is older than the buffer window.
          send(self(), {:initial_render, agent_uri})
        end

        {:ok,
         socket
         |> assign(:not_found, false)
         |> assign(:agent_uri, agent_uri)
         |> assign(:flash_error, nil)
         |> assign(:dispatch_target, dispatch_target_for(agent_uri))
         |> assign_caller(session)}

      _ ->
        {:ok, assign(socket, :not_found, true) |> assign(:bad_uri, encoded_uri)}
    end
  end

  defp assign_caller(socket, _session) do
    # PR #123 hardening: on_mount hook set current_entity_uri; admin
    # fallback deleted (was a public-WS-reconnect privilege-escalation
    # path pre-hardening).
    caller_uri = socket.assigns.current_entity_uri

    caller_caps =
      if URI.to_string(caller_uri) == URI.to_string(Ezagent.Entity.User.admin_uri()) do
        Ezagent.Entity.User.admin_caps()
      else
        Ezagent.Identity.list_caps_for(caller_uri)
      end

    socket
    |> assign(:caller_uri, caller_uri)
    |> assign(:caller_caps, caller_caps)
  end

  # PR #146: dispatch directly to the agent URI (pty-input://default
  # synthetic singleton dissolved per SPEC v2 §5.7).
  defp dispatch_target_for(%URI{} = agent_uri),
    do: URI.parse(URI.to_string(agent_uri) <> "?action=pty.write")

  # PR #141 + #145: entity:// scheme; agent URIs are entity://agent/<flavor>_<name>.
  defp parse_agent_uri(encoded) do
    decoded = URI.decode_www_form(encoded)

    case URI.new(decoded) do
      {:ok, %URI{scheme: "entity", host: "agent", path: "/" <> name} = uri}
      when is_binary(name) and name != "" ->
        {:ok, uri}

      _ ->
        :error
    end
  end

  @impl true
  def handle_info({:pty_output, _agent_uri, chunk}, socket) do
    {:noreply, push_event(socket, "pty_chunk", %{bytes: chunk})}
  end

  # PR #128 — push the PtyServer's accumulated stdout buffer to
  # xterm immediately on mount, then trigger a winsize nudge to
  # provoke a fresh TUI redraw. Both fail silently if the agent
  # isn't a live PtyServer (e.g. v2-only Channel-bridged agents
  # with no local PTY).
  def handle_info({:initial_render, agent_uri}, socket) do
    case Ezagent.PluginCc.PtyServer.snapshot_buffer(agent_uri) do
      {:ok, buf} when byte_size(buf) > 0 ->
        socket = push_event(socket, "pty_chunk", %{bytes: buf})
        _ = Ezagent.PluginCc.PtyServer.trigger_redraw(agent_uri)
        {:noreply, socket}

      _ ->
        _ = Ezagent.PluginCc.PtyServer.trigger_redraw(agent_uri)
        {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("pty_input", %{"bytes" => bytes}, socket) when is_binary(bytes) do
    # PR #146 — args no longer carry agent_uri; the dispatch target IS
    # the agent URI, and `Behavior.Pty.invoke/4` reads `ctx.self_uri`.
    inv = %Ezagent.Invocation{
      target: socket.assigns.dispatch_target,
      mode: :cast,
      args: %{bytes: bytes},
      ctx: %{
        caller: socket.assigns.caller_uri,
        caps: socket.assigns.caller_caps,
        reply: :ignore
      }
    }

    case Ezagent.Invocation.dispatch(inv) do
      {:ok, _} ->
        {:noreply, socket}

      :ok ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :flash_error,
           "Unauthorized — need agent.pty.write cap on this agent. " <>
             "Ask admin to grant it."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Input failed: #{inspect(reason)}")}
    end
  end

  def handle_event("pty_resize", %{"cols" => _cols, "rows" => _rows}, socket) do
    # v1: best-effort log only. Phase 5 PR 4 follow-up could dispatch a
    # pty/resize action; not blocking the demo.
    {:noreply, socket}
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities/agents"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
      <h1>Agent URI invalid</h1>
      <p><code>{@bad_uri}</code></p>
      <p><a href="/identities/agents" style="color: #0969da;">← Agents</a></p>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities/agents"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Pty-Web: <code>{URI.to_string(@agent_uri)}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <a href={"/identities/agents/#{URI.encode_www_form(URI.to_string(@agent_uri))}"} style="color: #0969da;">← Agent status</a>
          <span style="margin-left: 16px;">
            Input → <code>Ezagent.Invocation.dispatch</code> → CapBAC → audit → PTY.
          </span>
        </p>
      </header>

      <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 12px;">
        {@flash_error}
      </p>

      <div
        id={"pty-terminal-" <> Base.url_encode64(URI.to_string(@agent_uri), padding: false)}
        phx-hook="PtyTerminal"
        phx-update="ignore"
        style="margin-top: 16px; height: 540px; background: #1e1e1e; border: 1px solid #333; border-radius: 4px; padding: 8px;"
      ></div>

      <p style="font-size: 11px; color: #57606a; margin-top: 8px;">
        Type to send input. Output streams via <code>pty:output:&lt;agent_uri&gt;</code> PubSub.
      </p>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
