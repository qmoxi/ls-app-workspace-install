#!/usr/bin/env bash
#
# LiveShopper AWS WorkSpace — one-shot bootstrap entry (public).
# https://github.com/qmoxi/ls-app-workspace-install
#
# Fresh Ubuntu 24.04 WorkSpace:
#   curl -fsSL --proto '=https' --tlsv1.2 \
#     https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh | bash
#
# What this script does:
#   1. apt: git, openssh-client, ca-certificates
#   2. SSH deploy key (generate if missing)
#   3. Pause — you paste the public key into GitHub (qmoxi/ls-app deploy keys, allow write)
#   4. git clone git@github.com:qmoxi/ls-app.git
#   5. exec private bootstrap-workspace.sh (Node, MySQL, Playwright, Cursor, dock, …)
#
# Env:
#   REPO_DIR          default /home/build/ls-app
#   LS_INSTALL_BRANCH default main
#   LS_SKIP_DEPLOY_KEY_PROMPT=1  re-run without pause (key already on GitHub)

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/build/ls-app}"
LS_INSTALL_BRANCH="${LS_INSTALL_BRANCH:-main}"
LS_REPO_SSH="git@github.com:qmoxi/ls-app.git"
DEPLOY_KEY="${HOME}/.ssh/id_ed25519_ls_app_deploy"
DEPLOY_PUB="${DEPLOY_KEY}.pub"
GITHUB_KEYS_URL="https://github.com/qmoxi/ls-app/settings/keys"

log() { echo -e "\033[1;36m[ls-install]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ls-install]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ls-install]\033[0m $*" >&2; exit 1; }

usage() {
	cat <<EOF
Usage: install.sh

Environment:
  REPO_DIR=${REPO_DIR}
  LS_INSTALL_BRANCH=${LS_INSTALL_BRANCH}
  LS_SKIP_DEPLOY_KEY_PROMPT=1   skip "Press Enter" after adding deploy key

One-liner:
  curl -fsSL --proto '=https' --tlsv1.2 \\
    https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh | bash
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

[[ "$(id -u)" -eq 0 ]] && die "Run as your WorkSpace user, not root."

# ------------------------------------------------------------------------------
log "1/5 apt prerequisites"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq git openssh-client ca-certificates

# ------------------------------------------------------------------------------
log "2/5 SSH deploy key"
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if [[ ! -f "${DEPLOY_KEY}" ]]; then
	ssh-keygen -t ed25519 -N "" -f "${DEPLOY_KEY}" -C "ls-workspace-$(hostname -s)"
fi
chmod 600 "${DEPLOY_KEY}"
chmod 644 "${DEPLOY_PUB}"

SSH_CONFIG="${HOME}/.ssh/config"
if ! grep -q 'Host github.com' "${SSH_CONFIG}" 2>/dev/null; then
	mkdir -p "${HOME}/.ssh"
	{
		echo ""
		echo "Host github.com"
		echo "  IdentityFile ${DEPLOY_KEY}"
		echo "  IdentitiesOnly yes"
	} >> "${SSH_CONFIG}"
	chmod 600 "${SSH_CONFIG}"
fi

if ! grep -q 'github.com' "${HOME}/.ssh/known_hosts" 2>/dev/null; then
	ssh-keyscan -H github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
	chmod 644 "${HOME}/.ssh/known_hosts"
fi

# ------------------------------------------------------------------------------
log "3/5 Add deploy key on GitHub (allow write access)"
echo ""
echo "  Public key (paste into Deploy keys):"
echo "  ${GITHUB_KEYS_URL}"
echo ""
cat "${DEPLOY_PUB}"
echo ""

if [[ "${LS_SKIP_DEPLOY_KEY_PROMPT:-}" != "1" ]]; then
	if [[ -t 0 ]]; then
		read -rp "Press Enter after the deploy key is added on GitHub (with write access)... "
	else
		warn "Non-interactive shell — set LS_SKIP_DEPLOY_KEY_PROMPT=1 if the key is already on GitHub"
		die "Cannot continue without deploy key on GitHub"
	fi
fi

# Quick SSH check (may fail until key is registered)
if ! ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -qiE 'successfully authenticated|Hi qmoxi'; then
	warn "ssh git@github.com did not confirm auth yet — if clone fails, fix the deploy key and re-run"
fi

# ------------------------------------------------------------------------------
log "4/5 Clone ls-app → ${REPO_DIR}"
REPO_PARENT="$(dirname "${REPO_DIR}")"
if [[ ! -d "${REPO_PARENT}" ]]; then
	sudo mkdir -p "${REPO_PARENT}"
	sudo chown "${USER}:${USER}" "${REPO_PARENT}" 2>/dev/null || sudo chown "${USER}" "${REPO_PARENT}"
fi

if [[ ! -d "${REPO_DIR}/.git" ]]; then
	git clone --branch "${LS_INSTALL_BRANCH}" "${LS_REPO_SSH}" "${REPO_DIR}"
else
	log "    repo exists — fetching"
	git -C "${REPO_DIR}" fetch --all --tags --quiet
	if [[ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
		git -C "${REPO_DIR}" pull --rebase --quiet || true
	fi
fi

BOOTSTRAP="${REPO_DIR}/infra/workspaces/bootstrap-workspace.sh"
[[ -x "${BOOTSTRAP}" || -f "${BOOTSTRAP}" ]] || die "Missing ${BOOTSTRAP} after clone"

# ------------------------------------------------------------------------------
log "5/5 Run bootstrap-workspace.sh"
export REPO_DIR
export REPO_URL="${LS_REPO_SSH}"
exec bash "${BOOTSTRAP}"
