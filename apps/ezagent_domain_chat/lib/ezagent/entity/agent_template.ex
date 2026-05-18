defmodule Ezagent.Entity.AgentTemplate do
  @moduledoc """
  AgentTemplate Kind — what a spawnable Agent looks like (Phase 7
  PR 37).

  Per SPEC D7-2 + Allen 2026-05-18: "AgentTemplate 不需要过于复杂,
  类似 Claude AgentSDK 那样,指定工作目录,加载指定 setting 目录等等".

  An AgentTemplate is a **named, persistent pointer to a sandbox**
  (a directory tree that contains `.claude/settings.json`, MCP config,
  hooks, skills, plugins, credentials) plus a small cap policy.
  Instances are spawned by `Ezagent.Entity.Agent.spawn/4` (PR 40) and
  composed into team configurations by `Ezagent.Entity.SessionTemplate`
  (PR 38). The orchestrator agent (PR 45+) selects from registered
  AgentTemplates via its `list_templates` and `add_agent_slot` tools.

  ## URI shape

  `template://agent/<name>` (no version suffix — AgentTemplates are
  human-edited and versionless for now; bump to versioned shape if
  Phase 8+ adds blueprint synthesis or auto-evolution).

  ## Slice schema (per SPEC §AgentTemplate, final v3)

      %{
        # metadata
        name:               String.t(),
        description:        String.t(),

        # PTY launch params (Agent.spawn/4 translates these to erlexec
        # env + CLI args when starting the underlying claude process)
        working_directory:  String.t(),
        claude_config_dir:  String.t(),
        settings_path:      String.t() | nil,  # --settings override
        mcp_config_path:    String.t() | nil,  # --mcp-config override
        api_key_helper:     String.t() | nil,  # macOS multi-agent only

        # ESR side
        default_caps:       [Ezagent.Capability.t()],
        created_by:         URI.t() | nil,
        created_at:         DateTime.t()
      }

  **What is NOT in the slice** (deliberately): prompt, model, effort,
  tools whitelist, MCP servers. All of those live in the pointed-at
  `claude_config_dir` (or the explicit `settings_path` override).
  ESR doesn't re-model what CC already encodes — AgentTemplate is a
  sandbox pointer + cap policy, not a full agent spec.

  ## Persistence

  `{:snapshot, :on_change}` — AgentTemplates are durable
  configuration data; restart must restore the same set of
  templates the orchestrator can choose from.

  ## Spawn lifecycle

  AgentTemplate Kinds materialize either:
  - At admin-driven creation time (LV form / `mix
    esr.agent_template.create`) — direct `SpawnRegistry.spawn/1`
    + grant Identity.update_slice with the supplied config.
  - At boot via snapshot reload (ReadyGate replays the slice).

  No automatic spawn on first reference — operators must explicitly
  create AgentTemplates. The cc-orchestrator's seed template is
  installed at boot in dev profile (PR 45 deliverable).

  ## macOS Keychain caveat

  On macOS, CC credentials live in Keychain regardless of
  `CLAUDE_CONFIG_DIR`. Multi-agent on a single OS user shares
  Keychain credential access. Mitigations:
  - Populate `api_key_helper` with a per-template helper script that
    rotates keys (per `docs/onboarding/adding-a-plugin.md` worked
    example, PR 51 deliverable).
  - Or run each agent under a separate OS user.
  - Or accept the shared credential on dev macOS; production runs on
    Linux where `CLAUDE_CONFIG_DIR` fully isolates.
  """

  @behaviour Ezagent.Kind

  @impl Ezagent.Kind
  def type_name, do: :agent_template

  @impl Ezagent.Kind
  def behaviors, do: [Ezagent.Behavior.Identity]

  @impl Ezagent.Kind
  def persistence, do: {:snapshot, :on_change}
end
