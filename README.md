# ls-app-workspace-install

Public bootstrap entry for **AWS WorkSpaces** (Ubuntu 24.04) used with the private [`qmoxi/ls-app`](https://github.com/qmoxi/ls-app) recording/migration station.

## One-liner (fresh WorkSpace)

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

## What happens

| Phase | Script | Action |
|-------|--------|--------|
| Entry | `install.sh` (this repo) | `git`, `openssh-client`, SSH deploy key, **you paste key on GitHub**, `git clone` |
| Full station | `ls-app/infra/workspaces/bootstrap-workspace.sh` | Node 24 + Corepack pnpm, MySQL + `mysqlbinlog`, Playwright, AppImage Cursor, GNOME dock, desktop launchers, `tests/.env`, tunnel unit |

**Manual step:** during `install.sh`, add the printed public key at  
<https://github.com/qmoxi/ls-app/settings/keys> — enable **Allow write access** (recording launcher pushes).

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `REPO_DIR` | `/home/build/ls-app` | Clone path |
| `LS_BUILD_DIR` | `/home/build` | Build root; mirror `ls.tgz` at `${LS_BUILD_DIR}/ls.tgz` |
| `LS_MIRROR_REMOTE_TGZ` | `${LS_BUILD_DIR}/ls.tgz` | Remote path on mirror WorkSpace for legacy PHP scp |
| `LS_MIRROR_REPO` | `/home/build/ls-app` | Remote path on mirror for `tests/.env` scp |
| `LS_INSTALL_BRANCH` | `main` | Branch to clone |
| `LS_SKIP_DEPLOY_KEY_PROMPT` | unset | Set `1` to skip Enter prompt if key already registered |

## Re-run full bootstrap (repo already cloned)

```bash
REPO_DIR=/home/build/ls-app /home/build/ls-app/infra/workspaces/bootstrap-workspace.sh
```

## Docs in ls-app

- [infra/workspaces/README.md](https://github.com/qmoxi/ls-app/blob/main/infra/workspaces/README.md)
- [docs/WORKSPACE_RECORDING_STATION.md](https://github.com/qmoxi/ls-app/blob/main/docs/WORKSPACE_RECORDING_STATION.md)
