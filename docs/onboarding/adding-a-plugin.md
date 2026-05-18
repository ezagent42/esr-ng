# Adding a plugin to ESR

This walks you through writing a new plugin from scratch — concretely, a hypothetical **Slack adapter** (`esr_plugin_slack`). The same shape applies to any IM adapter (Discord, Telegram, etc.) or any plugin that adds new Kinds + Behaviors.

## What is a plugin in ESR?

A plugin is an OTP application under `apps/esr_plugin_<name>/` that:

1. Depends on `:esr_core` (and optionally domain apps like `:esr_domain_chat`).
2. Registers Behaviors / spawn fns / Template Classes / routing tables at boot via its `Application.start/2`.
3. Optionally ships its own Kinds, Behaviors, Template Classes.

ESR core never references any plugin module. Plugins are wired in at runtime via the four registry families (Kind / Behavior / Routing / Spawn / Template). This is the **plugin isolation north star** — adding a plugin doesn't recompile core; removing one doesn't break others.

## Concrete walkthrough — `esr_plugin_slack`

### Step 1 — scaffold the OTP app

From repo root:

```bash
cd apps
mix new esr_plugin_slack --module EsrPluginSlack --sup
```

The `--sup` flag generates a supervision tree (`EsrPluginSlack.Application`), which is what ESR's plugin contract requires.

### Step 2 — declare dependencies

In `apps/esr_plugin_slack/mix.exs`:

```elixir
defp deps do
  [
    {:esr_core, in_umbrella: true},
    {:esr_domain_chat, in_umbrella: true},
    {:slack_sdk, "~> 0.5"}   # hypothetical
  ]
end
```

Then add `:esr_plugin_slack` to the umbrella's `mix.exs` if needed (most umbrellas auto-discover).

### Step 3 — model the destination as a Receiver Kind

If your plugin sends messages OUT of ESR (Slack workspace → users), the destination MUST be a Receiver Kind (Decision #127 — see `docs/notes/plugin-receiver-kind-contract.md`).

Create `apps/esr_plugin_slack/lib/esr/entity/slack_channel.ex`:

```elixir
defmodule Esr.Entity.SlackChannel do
  @moduledoc """
  Slack channel as an ESR Receiver Kind. URI scheme `slack://`,
  authority = Slack channel ID (e.g. C12345). Receiving a Message
  triggers an HTTP POST to Slack's chat.postMessage API.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :slack_channel

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.SlackReceive]

  @impl Esr.Kind
  def persistence, do: :on_terminate
end
```

### Step 4 — implement the Behavior

Create `apps/esr_plugin_slack/lib/esr/behavior/slack_receive.ex`:

```elixir
defmodule Esr.Behavior.SlackReceive do
  @behaviour Esr.Behavior

  @impl Esr.Behavior
  def state_slice, do: :slack

  @impl Esr.Behavior
  def init_slice(_args), do: %{}

  @impl Esr.Behavior
  def interface do
    %{
      receive: %{
        args: %{message: :map},
        returns: %{},
        modes: [:cast]
      }
    }
  end

  @impl Esr.Behavior
  def invoke(:receive, slice, %{message: msg}, ctx) do
    # ctx.self_uri = slack://C12345
    channel_id = ctx.self_uri.host
    text = body_text(msg.body)

    EsrPluginSlack.Client.send_message(channel_id, text)
    # Always {:ok, slice} from a Receiver Kind — no slice changes
    {:ok, slice}
  end

  defp body_text(%{text: t}), do: t
  defp body_text(_), do: ""
end
```

### Step 5 — wire it all together in Application.start/2

Edit `apps/esr_plugin_slack/lib/esr_plugin_slack/application.ex`:

```elixir
defmodule EsrPluginSlack.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Register Behavior for the new Kind + action
    :ok = Esr.BehaviorRegistry.register(
      Esr.Entity.SlackChannel,
      :receive,
      Esr.Behavior.SlackReceive
    )

    # Register spawn fn for the slack:// scheme (URI-only per Decision #65)
    :ok = Esr.SpawnRegistry.register("slack", fn uri ->
      DynamicSupervisor.start_child(
        EsrPluginSlack.SlackChannelSupervisor,
        {Esr.Kind.Server, {Esr.Entity.SlackChannel, %{uri: uri}}}
      )
    end)

    children = [
      {DynamicSupervisor, name: EsrPluginSlack.SlackChannelSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
```

### Step 6 — set up routing

When ESR receives a message in a session and you want it sent to Slack, you need a routing rule. Two paths:

- **Programmatic (in your plugin's seed code)**:
  ```elixir
  matcher = Esr.Routing.Matcher.in_session(URI.new!("session://main"))
  receivers = ["slack://C12345"]
  Esr.Routing.RuleStore.add(MentionRouting, matcher, receivers, "user://admin", [])
  Esr.Routing.RuleStore.load_into_registry(MentionRouting)
  ```
- **LV / CLI (admin-driven)**: via `/admin/routing` form or `mix esr.routing.add_rule`.

Always pass `workspace_uri:` if you want the rule scoped (per invariant 4 — see `esr-developer` skill).

### Step 7 — handle inbound (if Slack→ESR is in scope)

For Slack→ESR (user types in Slack, ESR receives), you need:

1. An inbound transport (HTTP webhook or WS sidecar, similar to `EsrPluginFeishu.WsClient`).
2. An `InboundDispatcher` that resolves Slack sender → ESR user URI, looks up the session, dispatches `Chat.send`.

**Critical** (Decision #134): use `mode: :call` not `:cast` so cap denial returns synchronously, and your handler sends an error message back to the Slack channel + a reaction emoji. Silent drop on cap denial is the bug `feedback_explicit_stop_signal_after_feishu` was created to prevent.

Reference implementation: `apps/esr_plugin_feishu/lib/esr/plugin_feishu/inbound_dispatcher.ex`.

### Step 8 — install + test

If the plugin compiles, install it into a running ESR (no phx restart):

```bash
mix esr.plugin.install /path/to/esr-ng/apps/esr_plugin_slack
```

You should see:
```
Loading application :esr_plugin_slack ...
Starting application :esr_plugin_slack (and dependencies) ...
✓ Started: :esr_plugin_slack
Registered Behaviors:
  • Esr.Behavior.SlackReceive
```

Then dispatch a test:

```elixir
slack_uri = URI.new!("slack://C12345-test")
{:ok, _} = Esr.SpawnRegistry.spawn(slack_uri)
msg = Esr.Message.new(URI.new!("user://admin"), %{text: "hello slack", attachments: []})
inv = %Esr.Invocation{
  target: URI.new!("slack://C12345-test/behavior/slack/receive"),
  mode: :cast,
  args: %{message: msg},
  ctx: %{caller: URI.new!("user://admin"), caps: Esr.Entity.User.admin_caps(), reply: :ignore}
}
Esr.Invocation.dispatch(inv)
```

You should see your Slack API call fire.

## Common gotchas

### Gotcha: `Mix.env()` in `Application.start/2` returns BUILD-time env

`mix esr.plugin.install` reads the plugin's compiled `.app` file. If you used `Mix.env()` to switch behavior at boot (e.g. `if Mix.env() != :test, do: seed_initial_data()`), the value reflects the env the plugin was COMPILED with, not the host's runtime env.

Fix: use `System.get_env("MIX_ENV")` (runtime read) or skip env-dependent boot logic entirely.

### Gotcha: Plugin's `Application.start/2` runs at install time

`ensure_all_started` triggers your `Application.start/2`. If it has side-effects (HTTP calls to set up webhooks, DB seeds), they run at install time. Make them idempotent — installing twice should be a no-op.

### Gotcha: TemplateRegistry strict-duplicate

If your plugin registers a Template Class with a name another plugin already claims, `TemplateRegistry.register/1` returns `{:error, {:duplicate, existing, attempted}}`. Pick a unique name (project convention: prefix with your plugin name, e.g. `"slack.channel.standard"`).

### Gotcha: PubSub.broadcast bypass

Tempted to `Phoenix.PubSub.broadcast(EsrCore.PubSub, "slack:incoming", msg)` from your WS handler? **Refuse this temptation.** That bypasses dispatch + CapBAC + audit. Build a Receiver Kind (Decision #127) and route through `Esr.Invocation.dispatch/1` instead.

## Reference plugins to study

- `apps/esr_plugin_echo/` — smallest, simplest. Read this first.
- `apps/esr_plugin_feishu/` — fullest production plugin. Inbound + outbound + WS sidecar + user binding + react path + cap delegation.
- `apps/esr_plugin_cc_pty/` — non-IM plugin (terminal PTY). Different shape but same plugin contract.

## When you're done

- Run your invariant test (write one — see `docs/onboarding/adding-kind-behavior-template.md` §"How to write an invariant test").
- Run the cross-PR invariants (see `docs/onboarding/first-30-days.md` §week-4).
- SPEC_REVIEW 8-item checklist (per `phase-specs/phase7/SPEC.md` §SPEC_REVIEW walkthrough).
- Open PR with the checklist in the body.

Welcome to the team.
