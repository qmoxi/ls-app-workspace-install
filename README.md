# ls-app-workspace-install

Public bootstrap entry for **AWS WorkSpaces** (Ubuntu 24.04) used with the private [`qmoxi/ls-app`](https://github.com/qmoxi/ls-app) recording/migration station.

## Fresh WorkSpace — recording only

```bash
curl -fsSL --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh | bash
```

Review before running (recommended once):

```bash
curl -fsSL --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## Fresh WorkSpace — migration (golden-migrate)

Run in order after the box is online:

```bash
# 1. Recording baseline (Node, Playwright, legacy PHP, Cursor, tests/.env)
curl -fsSL --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh | bash

# 2. Migration tools (cm/cass, MCP, server+client, Xvfb)
#    From ls-app after git pull (works now):
bash /home/build/ls-app/scripts/workspaces/ls-workspace-install/install-migration-tools.sh
#    Or public curl (after workspace-install repo is pushed):
# curl -fsSL .../install-migration-tools.sh | bash

# 3. Golden DB (Docker + ZFS + base@T) — needs AWS SSO
aws sso login --profile ls-admin
bash /home/build/ls-app/scripts/workspaces/ls-workspace-install/install-golden-db.sh
# First run seeds ~22 GB into ZFS — typically 10–30 minutes. Do not interrupt.
# If Docker was just installed, sign out/in once if the script says docker is unavailable.

# Confirm fast-reset snapshot exists:
sudo zfs list tank/lsgold/base@T
```

Or steps 2+3 in one shot (still needs `aws sso login` first):

```bash
aws sso login --profile ls-admin
curl -fsSL --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install-migration.sh | bash
```

Then **fully restart Cursor** and verify:

```bash
cd /home/build/ls-app
node cursor-migrate/preflight.mjs --mode golden --recover
```

## What happens

| Phase | Script | Action |
|-------|--------|--------|
| Entry | `install.sh` | `git`, SSH deploy key, **paste key on GitHub**, `git clone`, `bootstrap-workspace.sh` |
| Full station | `ls-app/scripts/workspaces/bootstrap-workspace.sh` | Node 24 + pnpm, MySQL + `mysqlbinlog`, Playwright, Cursor, `tests/.env`, tunnel |
| Migration tools | `install-migration-tools.sh` | rg, Xvfb :99, server/client pnpm, cm+cass, codebase-memory-mcp, git hooks |
| Golden DB | `install-golden-db.sh` | Docker CE, ZFS pool, ECR `ls-mysql` seed → `base@T`, `db-target local` |
| All migration | `install-migration.sh` | tools + golden DB (convenience wrapper) |

**Manual steps:**

- During `install.sh`: add deploy key at <https://github.com/qmoxi/ls-app/settings/keys> — **Allow write access**
- Before `install-golden-db.sh`: `aws sso login --profile ls-admin`
- After first Docker install on a new box: **sign out/in** if `install-golden-db.sh` reports docker socket unavailable (AD group activation)
- After migration tools: fully restart Cursor (MCP)

**Golden DB verify** (must show `base@T` — without it resets copy 22 GB and take minutes):

```bash
sudo zfs list tank/lsgold/base@T
bash /home/build/ls-app/cursor-migrate/db-container.sh status --scenario scheduler-UrgentLog
# → "zfs base: tank/lsgold/base@T present"
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `REPO_DIR` | `/home/build/ls-app` | Clone path |
| `LS_BUILD_DIR` | `/home/build` | Build root; mirror `ls.tgz` at `${LS_BUILD_DIR}/ls.tgz` |
| `LS_MIRROR_REMOTE_TGZ` | `${LS_BUILD_DIR}/ls.tgz` | Remote path on mirror WorkSpace for legacy PHP scp |
| `LS_MIRROR_REPO` | `/home/build/ls-app` | Remote path on mirror for `tests/.env` scp |
| `LS_INSTALL_BRANCH` | `main` | Branch to clone |
| `LS_SKIP_DEPLOY_KEY_PROMPT` | unset | Set `1` to skip Enter prompt if key already registered |
| `AWS_PROFILE` | `ls-admin` | SSO profile for ECR + Secrets Manager |
| `IMAGE_TAG` | `latest` | ECR `ls-mysql` tag for golden DB seed |

## Re-run (repo already cloned)

```bash
REPO_DIR=/home/build/ls-app /home/build/ls-app/scripts/workspaces/bootstrap-workspace.sh
REPO_DIR=/home/build/ls-app bash /home/build/ls-app/scripts/workspaces/setup-migration-workspace.sh
```

## Docs in ls-app

- [scripts/workspaces/README.md](https://github.com/qmoxi/ls-app/blob/main/scripts/workspaces/README.md)
- [docs/golden-master-migration.md](https://github.com/qmoxi/ls-app/blob/main/docs/golden-master-migration.md)
- [docs/WORKSPACE_RECORDING_STATION.md](https://github.com/qmoxi/ls-app/blob/main/docs/WORKSPACE_RECORDING_STATION.md)
