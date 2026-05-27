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
#   LS_SKIP_DEPLOY_KEY_PROMPT=1  skip wait loop (fail immediately if key not on GitHub yet)
#
# Run from an interactive terminal (GNOME Terminal on the WorkSpace). This works:
#   curl -fsSL https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh | bash
# When piped, the script re-attaches stdin/stdout to /dev/tty so prompts work.

set -euo pipefail

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install.sh"

REPO_DIR="${REPO_DIR:-/home/build/ls-app}"
LS_INSTALL_BRANCH="${LS_INSTALL_BRANCH:-main}"
LS_REPO_SSH="git@github.com:qmoxi/ls-app.git"
DEPLOY_KEY="${HOME}/.ssh/id_ed25519_ls_app_deploy"
DEPLOY_PUB="${DEPLOY_KEY}.pub"
GITHUB_KEYS_URL="https://github.com/qmoxi/ls-app/settings/keys"

log() { echo -e "\033[1;36m[ls-install]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ls-install]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ls-install]\033[0m $*" >&2; exit 1; }

# curl | bash feeds the script on stdin (not a TTY). Re-run attached to the desktop terminal.
ensure_interactive_shell() {
	if [[ -t 0 ]]; then
		return 0
	fi
	if [[ -n "${LS_INSTALL_REEXEC:-}" ]]; then
		die "Still non-interactive after re-exec. Use: curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh"
	fi
	if [[ -r /dev/tty ]]; then
		echo "[ls-install] Attaching to your terminal for interactive prompts…" >/dev/tty
		export LS_INSTALL_REEXEC=1
		exec </dev/tty >/dev/tty 2>/dev/tty bash -i -c "$(curl -fsSL "${INSTALL_SCRIPT_URL}")" "$@"
	fi
	die "Interactive shell required (e.g. GNOME Terminal on the WorkSpace).

  curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh"
}

github_ssh_ok() {
	ssh -i "${DEPLOY_KEY}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 \
		-T git@github.com 2>&1 | grep -qiE 'successfully authenticated|Hi qmoxi'
}

prompt_user() {
	local msg="$1"
	if [[ -t 0 ]]; then
		read -rp "${msg}"
		return 0
	fi
	if [[ -r /dev/tty ]]; then
		read -rp "${msg}" </dev/tty
		return 0
	fi
	return 1
}

wait_for_github_deploy_key() {
	echo ""
	echo "  Public key (paste into Deploy keys — Allow write access):"
	echo "  ${GITHUB_KEYS_URL}"
	echo ""
	cat "${DEPLOY_PUB}"
	echo ""

	if github_ssh_ok; then
		log "    GitHub deploy key already works"
		return 0
	fi

	if [[ "${LS_SKIP_DEPLOY_KEY_PROMPT:-}" == "1" ]]; then
		die "Deploy key not on GitHub yet (or write access disabled). Add the key above, or unset LS_SKIP_DEPLOY_KEY_PROMPT."
	fi

	log "    Waiting until this key is saved on GitHub (press Enter after each attempt)…"

	while ! github_ssh_ok; do
		prompt_user "Press Enter after the deploy key is saved on GitHub (Allow write access)... " \
			|| die "Interactive terminal required for prompts."
		if ! github_ssh_ok; then
			warn "    GitHub SSH not working yet — add the key at ${GITHUB_KEYS_URL}"
		fi
	done
	log "    GitHub SSH OK"
}

usage() {
	cat <<EOF
Usage: install.sh

Environment:
  REPO_DIR=${REPO_DIR}
  LS_INSTALL_BRANCH=${LS_INSTALL_BRANCH}
  LS_SKIP_DEPLOY_KEY_PROMPT=1   skip "Press Enter" after adding deploy key

One-liner (from GNOME Terminal — re-attaches to /dev/tty when piped):
  curl -fsSL ${INSTALL_SCRIPT_URL} | bash
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

[[ "$(id -u)" -eq 0 ]] && die "Run as your WorkSpace user, not root."

# Must run before sudo/read prompts (curl | bash is not a TTY until we re-exec).
ensure_interactive_shell "$@"

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
wait_for_github_deploy_key

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
