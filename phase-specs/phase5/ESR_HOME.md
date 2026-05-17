# ESR_HOME — runtime persistence layout for esr-ng

**Status:** DRAFT 2026-05-17 (Phase 5 precursor).
**Source:** lessons from old esrd-dev (`~/.esrd-dev/default/`); adapted for esr-ng's `SQLite-as-database` + `file-as-credentials` split.

## Why ESR_HOME exists

Phase 0-4.5 stored everything in the project's working directory:
- `esr_core_dev.db` SQLite file at repo root
- Audit / messages / snapshots all inside it
- No external credentials yet (CC bridge uses no auth)

Phase 5 adds **credentials that must NOT live in git**:
- Feishu app `app_id` + `app_secret` + webhook encrypt_key
- CC channel per-instance connect tokens
- Future: Slack / other adapter creds

Putting these in a separate user-home directory:
1. Keeps secrets out of the repo (gitignore safety)
2. Lets the same repo run multiple ESR profiles (dev / staging / personal)
3. Survives `git clean -fdx` and worktree switches
4. Matches the operator mental model: "one ESR instance has one home"

## Directory layout

```
$ESR_HOME/                      ← default: ~/.esr-ng
└── <profile>/                  ← default: "default"; multi-profile support
    ├── credentials/            ← secrets — NEVER commit, NEVER ship in tarballs
    │   ├── feishu.yaml         ← {app_id, app_secret, encrypt_key, verification_token}
    │   ├── cc-channels.yaml    ← {bridge_id: connect_token} per registered CC instance
    │   └── README.md           ← documents what each file should contain
    ├── db/
    │   └── esr_core.db         ← SQLite (moved from repo root)
    ├── snapshots/              ← Phase 4 Snapshot blob storage (currently repo-root)
    ├── logs/                   ← server logs (file rotation; ops-friendly)
    ├── plugins/
    │   └── <plugin_name>/
    │       └── config.yaml     ← per-plugin overrides (non-secret tunables)
    ├── pid                     ← `mix phx.server` write current PID
    └── port                    ← server port (default 4000; for `esr` CLI discovery)
```

Profile model: `~/.esr-ng/default/` is the implicit profile. `ESR_PROFILE=staging` would use `~/.esr-ng/staging/`. v1 ships just `default`; multi-profile is the framing not the impl.

## Environment contract

| Variable | Default | Purpose |
|---|---|---|
| `ESR_HOME` | `~/.esr-ng` | Root of all profiles |
| `ESR_PROFILE` | `default` | Active profile under `$ESR_HOME` |
| `ESR_DB_PATH` | `$ESR_HOME/$ESR_PROFILE/db/esr_core.db` | SQLite location |

`config/dev.exs` and `config/runtime.exs` read these env vars with sensible fallbacks (so existing `mix phx.server` in repo without setup still works — the fallbacks point at repo-local paths same as today, until the operator runs `mix esr.home.init`).

## Init flow

### `mix esr.home.init` (new mix task, Phase 5 prerequisite)

Idempotent setup:

1. Create `$ESR_HOME/$ESR_PROFILE/` skeleton (creds/, db/, snapshots/, logs/, plugins/)
2. If `credentials/feishu.yaml` missing → write empty template with `# REQUIRED: app_id, app_secret` comments
3. If `db/esr_core.db` missing → copy current repo-root `esr_core_dev.db` if present, else create empty (Ecto migrations run on next boot)
4. Print next-steps: "Fill in `$ESR_HOME/default/credentials/feishu.yaml` then restart server"

Output is a short summary table, e.g.:

```
ESR_HOME = /Users/allen/.esr-ng/default
  credentials/feishu.yaml      MISSING — template written; fill in app_id/app_secret
  credentials/cc-channels.yaml MISSING — template written; optional until Phase 5b
  db/esr_core.db               existing (1.4 MB)
  snapshots/                   empty
  logs/                        empty
```

### `mix esr.home.import_from_esrd_dev`

One-shot migration helper for operators who already had old `esrd-dev`:

1. Read `~/.esrd-dev/default/adapters/esr_helper_dev/config.yaml` → copy to `$ESR_HOME/default/credentials/feishu.yaml` (translating field names where they differ)
2. Read `~/.esrd-dev/default/chat_attached.yaml` → write to `$ESR_HOME/default/plugins/feishu/initial_bindings.yaml` so Phase 5a Template Loader can seed existing session ↔ chat bindings
3. Print what was imported; do NOT delete old `.esrd-dev`

## Security

- `$ESR_HOME` directory perms: `chmod 700` on init
- `credentials/*.yaml`: `chmod 600` on write
- Repo `.gitignore` adds `/.esr-ng/` defensively (case operator runs ESR with home pointed inside repo)
- `mix esr.home.init` refuses to write to a path that's inside a git working tree (unless `--inside-repo` override)

## Phase 5 dependency

5a (Feishu adapter) can't ship without ESR_HOME because credentials need a home. Hence this doc is **Phase 5 prerequisite**, landed before 5a PR.

5b (CC channel) uses `credentials/cc-channels.yaml` for per-instance connect tokens.

5c/5d don't need ESR_HOME directly but inherit the pattern (e.g. PTY logs could land in `logs/pty/<agent_uri>/`).

## Open questions for Allen

| # | Question | Recommendation |
|---|---|---|
| ESR_HOME-Q1 | Migrate `esr_core_dev.db` to `$ESR_HOME` immediately or only after Phase 5? | After Phase 5 — moving the DB mid-Phase-5 invites accidental data loss; do it as a dedicated `mix esr.home.adopt_db` PR |
| ESR_HOME-Q2 | Encrypt credentials at rest (libsodium key-derived from OS keychain)? | v1 plain YAML + chmod 600; encryption is Phase 6+ if real-world threat model emerges |
| ESR_HOME-Q3 | Profile per-workspace vs per-instance? | per-instance (matches old esrd-dev `default/`); a Workspace lives inside a profile, not above one |
