defmodule EzagentPluginLiveview.AgentNewLive do
  @moduledoc """
  Phase 8c PR-N (Allen 2026-05-20) — UI for creating new agents.

  Mounts at `/identities/agents/new`. Form fields:

  - **flavor** — dropdown over the built-in agent flavors
    (`cc / curl / echo`, matching `kind_module_from_flavor/1` in
    `EzagentDomainChat.Application`). Hard-coded for v1; future work
    can derive this list from `Ezagent.SpawnRegistry` once flavor
    registration becomes data-driven.
  - **name** — short identifier; UI composes the full URI
    `entity://agent/<flavor>_<name>`. A live preview line shows the
    composed URI as the user types (phx-change "preview").
  - **caps** — comma-separated cap specs in the
    `Ezagent.Capability.Parser` grammar (e.g. `chat.send, workspace.read`).
    Empty is fine — agents can be created with no caps and have caps
    granted later via `/identities/agents/<uri>/caps`.

  Submit (`create_agent`) runs the same backend path as
  `mix ezagent.agent.create`:

  1. Parse flavor + name → build `%URI{}`
  2. Validate name (non-empty, no `_` collision with flavor prefix)
  3. Refuse if the URI already exists in `KindRegistry` (no
     misleading "Create" on a noop — per memory
     `feedback_ui_no_misleading_buttons`)
  4. Parse caps via `Ezagent.Capability.Parser.parse/3`
  5. `Ezagent.SpawnRegistry.spawn/1`
  6. For each parsed cap: dispatch `identity.grant_cap` (same path as
     `EntityCapsLive`)
  7. `push_navigate(to: /identities/agents/<encoded>)`

  Wraps in `IdeShell.ide_shell` (workspace surface — agent creation
  is workflow, not config).
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  import Phoenix.Component

  alias Ezagent.{Capability, Invocation, KindRegistry}
  alias Phoenix.LiveView.JS

  # Flavors mirror `kind_module_from_flavor/1` in
  # `EzagentDomainChat.Application` (PR #149 §5.14). Order is
  # creation-frequency-descending: cc is the common case (Claude-Code
  # orchestrated agent), echo is the testing fixture, curl is the
  # external-HTTP variant.
  @flavors ~w(cc echo curl)

  # Phase 8c follow-up (Allen 2026-05-20) — cc agents need a PtyServer to
  # actually exec claude-code. PtyServer is started when a workspace's
  # `cc.agent` template references the agent_uri. Until this step exists,
  # AgentNewLive only created an identity skeleton ("Not running" forever).
  # We now also register the template inline as part of create_agent so a
  # fresh cc agent boots ready-to-use.
  #
  # Workspace target: hardcoded "default" for now. Per the
  # workspace=deployment-unit doc, current-workspace context is a Phase 9
  # concern; once it's a server-side concept this code reads from socket.
  @default_workspace_name "default"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:flavors, @flavors)
     |> assign(:flavor, "cc")
     |> assign(:name, "")
     |> assign(:caps_str, "")
     |> assign(:cwd, "")
     |> assign(:flash_error, nil)
     |> assign(:flash_info, nil)
     |> assign(:preview_uri, preview_uri("cc", ""))}
  end

  @impl true
  def handle_event("preview", %{"agent" => params}, socket) do
    flavor = Map.get(params, "flavor", socket.assigns.flavor)
    name = Map.get(params, "name", socket.assigns.name)
    caps_str = Map.get(params, "caps", socket.assigns.caps_str)
    cwd = Map.get(params, "cwd", socket.assigns.cwd)

    {:noreply,
     socket
     |> assign(:flavor, flavor)
     |> assign(:name, name)
     |> assign(:caps_str, caps_str)
     |> assign(:cwd, cwd)
     |> assign(:preview_uri, preview_uri(flavor, name))}
  end

  def handle_event("create_agent", %{"agent" => params}, socket) do
    flavor = Map.get(params, "flavor", "") |> String.trim()
    name = Map.get(params, "name", "") |> String.trim()
    caps_str = Map.get(params, "caps", "") |> String.trim()
    cwd = Map.get(params, "cwd", "") |> String.trim()

    with :ok <- validate_flavor(flavor),
         :ok <- validate_name(name),
         :ok <- validate_cwd_for_flavor(flavor, cwd),
         {:ok, agent_uri} <- compose_uri(flavor, name),
         :ok <- refuse_if_exists(agent_uri),
         {:ok, caps} <- Capability.Parser.parse(caps_str, caller_uri(socket)),
         {:ok, _pid} <- Ezagent.SpawnRegistry.spawn(agent_uri),
         :ok <- grant_all(agent_uri, caps, socket),
         :ok <- maybe_register_cc_template(flavor, agent_uri, cwd) do
      encoded = URI.encode_www_form(URI.to_string(agent_uri))
      {:noreply, push_navigate(socket, to: "/identities/agents/#{encoded}")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:flash_error, friendly_error(reason))
         |> assign(:flash_info, nil)
         |> assign(:flavor, flavor)
         |> assign(:name, name)
         |> assign(:caps_str, caps_str)
         |> assign(:cwd, cwd)
         |> assign(:preview_uri, preview_uri(flavor, name))}
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp validate_flavor(f) when f in @flavors, do: :ok
  defp validate_flavor(""), do: {:error, :flavor_required}
  defp validate_flavor(f), do: {:error, {:bad_flavor, f}}

  defp validate_name(""), do: {:error, :name_required}

  defp validate_name(name) do
    # Names are part of a URI path segment; restrict to a safe set so
    # we don't have to URL-encode the path on display. Matches the
    # informal convention used in seed data (`echo_default`,
    # `cc_demo-builder`) — alnum + dash + underscore.
    if name =~ ~r/\A[A-Za-z0-9][A-Za-z0-9_\-]*\z/ do
      :ok
    else
      {:error, {:bad_name, name}}
    end
  end

  # echo / curl flavors don't use a PtyServer; cwd is irrelevant.
  defp validate_cwd_for_flavor(flavor, _cwd) when flavor in ["echo", "curl"], do: :ok
  defp validate_cwd_for_flavor("cc", ""), do: {:error, :cwd_required_for_cc}

  defp validate_cwd_for_flavor("cc", cwd) do
    expanded = Path.expand(cwd)

    cond do
      not File.dir?(expanded) -> {:error, {:cwd_not_a_dir, cwd}}
      true -> :ok
    end
  end

  defp validate_cwd_for_flavor(_, _), do: :ok

  defp maybe_register_cc_template("cc", agent_uri, cwd) do
    tmpl_name = "cc.agent." <> agent_name(agent_uri)

    tmpl = %{
      "class" => "cc.agent",
      "agent_uri" => URI.to_string(agent_uri),
      "mode" => "local-pty",
      "cwd" => Path.expand(cwd)
    }

    case Ezagent.Workspace.add_template(@default_workspace_name, tmpl_name, tmpl) do
      :ok -> :ok
      {:error, reason} -> {:error, {:template_register_failed, reason}}
    end
  end

  defp maybe_register_cc_template(_other_flavor, _agent_uri, _cwd), do: :ok

  defp agent_name(%URI{path: "/" <> rest}) do
    # Phase 9 PR-2 (SPEC v3 §3): entity URI is /<workspace>/<entity_name>.
    case String.split(rest, "/", parts: 2) do
      [_workspace, entity_name] -> entity_name
      [name] -> name
    end
  end

  defp compose_uri(flavor, name) do
    full = "entity://agent/default/#{flavor}_#{name}"

    case URI.new(full) do
      {:ok, %URI{scheme: "entity", host: "agent", path: "/" <> _} = u} -> {:ok, u}
      _ -> {:error, {:bad_uri, full}}
    end
  end

  defp refuse_if_exists(uri) do
    case KindRegistry.lookup(uri) do
      :error -> :ok
      {:ok, _pid} -> {:error, {:already_exists, URI.to_string(uri)}}
    end
  end

  defp preview_uri(flavor, name) when is_binary(flavor) and is_binary(name) do
    cond do
      flavor == "" or name == "" -> "entity://agent/<flavor>_<name>"
      true -> "entity://agent/default/#{flavor}_#{name}"
    end
  end

  defp caller_uri(socket) do
    # Plumbed by EzagentWeb.LiveAuth.on_mount(:require_entity); falls
    # back to admin only if upstream auth broke (which would already
    # have redirected pre-mount, so this is belt-and-suspenders).
    Map.get(socket.assigns, :current_entity_uri) || Ezagent.Entity.User.admin_uri()
  end

  defp caller_caps(socket) do
    caller = caller_uri(socket)

    if URI.to_string(caller) == URI.to_string(Ezagent.Entity.User.admin_uri()) do
      Ezagent.Entity.User.admin_caps()
    else
      Ezagent.Identity.list_caps_for(caller)
    end
  end

  defp grant_all(_agent_uri, [], _socket), do: :ok

  defp grant_all(agent_uri, [cap | rest], socket) do
    target =
      URI.new!("#{URI.to_string(agent_uri)}?action=identity.grant_cap")

    case Invocation.dispatch(%Invocation{
           target: target,
           mode: :call,
           args: %{cap: cap},
           ctx: %{
             caller: caller_uri(socket),
             caps: caller_caps(socket),
             reply: :sync
           }
         }) do
      {:ok, _} -> grant_all(agent_uri, rest, socket)
      {:error, reason} -> {:error, {:grant_failed, cap, reason}}
    end
  end

  defp friendly_error(:flavor_required), do: "Flavor is required."
  defp friendly_error(:name_required), do: "Name is required."
  defp friendly_error({:bad_flavor, f}), do: "Unknown flavor: #{inspect(f)}. Choose cc / echo / curl."

  defp friendly_error({:bad_name, n}),
    do: "Name #{inspect(n)} must start with a letter or digit and contain only letters, digits, '-', or '_'."

  defp friendly_error({:bad_uri, s}), do: "Cannot build URI from inputs (got #{s})."
  defp friendly_error({:already_exists, uri}), do: "An agent already exists at #{uri}. Pick a different name."
  defp friendly_error({:grant_failed, cap, reason}),
    do: "Agent created but cap grant failed for #{inspect(cap)}: #{inspect(reason)}"

  defp friendly_error(:cwd_required_for_cc),
    do: "Working directory is required for cc agents (claude-code runs there)."

  defp friendly_error({:cwd_not_a_dir, cwd}),
    do: "Working directory #{inspect(cwd)} doesn't exist or isn't a directory."

  defp friendly_error({:template_register_failed, reason}),
    do: "Agent created but cc.agent template registration failed: #{inspect(reason)}"

  defp friendly_error(other), do: "Create failed: #{inspect(other)}"

  # ── render ─────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/default/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
      is_admin?={@is_admin?}
      workspaces={@workspaces}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900 dark:text-zinc-100">
          <.breadcrumb items={[{"Identities", "/identities"}, {"New agent", nil}]} />

          <.page_header title="New agent">
            <:subtitle>
              Spawns a new Agent Kind into the registry. Same backend as
              <code>mix ezagent.agent.create</code>.
            </:subtitle>
          </.page_header>

          <p :if={@flash_info} class="text-emerald-700 dark:text-emerald-300 text-sm mb-3">{@flash_info}</p>
          <p :if={@flash_error} class="text-red-700 dark:text-red-300 text-sm mb-3" id="flash-error">{@flash_error}</p>

          <.card class="max-w-2xl">
            <form
              id="agent-new-form"
              phx-change="preview"
              phx-submit="create_agent"
              class="flex flex-col gap-4"
            >
              <label class="flex flex-col gap-1">
                <span class="text-xs uppercase tracking-wide text-zinc-500">Flavor</span>
                <select
                  name="agent[flavor]"
                  class="block w-full px-3 py-2 text-sm rounded-md border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100"
                >
                  <option :for={f <- @flavors} value={f} selected={f == @flavor}>{f}</option>
                </select>
                <span class="text-[11px] text-zinc-500">
                  Which plugin runs this agent. <code>cc</code> = Claude-Code orchestrated;
                  <code>echo</code> = test fixture; <code>curl</code> = external HTTP agent.
                </span>
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs uppercase tracking-wide text-zinc-500">Name</span>
                <input
                  type="text"
                  name="agent[name]"
                  value={@name}
                  placeholder="demo"
                  autocomplete="off"
                  class="block w-full px-3 py-2 text-sm rounded-md border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-mono"
                />
                <span class="text-[11px] text-zinc-500">
                  Creates <code class="font-mono text-zinc-700 dark:text-zinc-300">{@preview_uri}</code>
                </span>
              </label>

              <label :if={@flavor == "cc"} class="flex flex-col gap-1">
                <span class="text-xs uppercase tracking-wide text-zinc-500">
                  Working directory <span class="text-red-600 dark:text-red-400">*</span>
                </span>
                <input
                  type="text"
                  name="agent[cwd]"
                  value={@cwd}
                  placeholder="/Users/you/Workspace/my-project"
                  autocomplete="off"
                  class="block w-full px-3 py-2 text-sm rounded-md border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-mono"
                />
                <span class="text-[11px] text-zinc-500">
                  Where <code>claude-code</code> runs. Required for <code>cc</code> flavor
                  — the PtyServer starts in this directory. Must exist on the host.
                  Registers a <code>cc.agent</code> template in workspace
                  <code>default</code> so the agent boots ready-to-use.
                </span>
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs uppercase tracking-wide text-zinc-500">Initial caps</span>
                <input
                  type="text"
                  name="agent[caps]"
                  value={@caps_str}
                  placeholder="chat.send, workspace.read"
                  autocomplete="off"
                  class="block w-full px-3 py-2 text-sm rounded-md border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-mono"
                />
                <span class="text-[11px] text-zinc-500">
                  Comma-separated <code>kind.behavior</code> specs (<code>Ezagent.Capability.Parser</code>).
                  Leave empty to create with no caps and grant them later.
                </span>
              </label>

              <div class="flex justify-end gap-2 pt-2 border-t border-zinc-200 dark:border-zinc-800">
                <.button variant="ghost" type="button" phx-click={JS.navigate("/identities")}>Cancel</.button>
                <.button variant="primary" type="submit">Create agent</.button>
              </div>
            </form>
          </.card>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

end
