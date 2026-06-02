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
#   1. apt: git, openssh-client, ca-certificates + global pull.rebase / rebase.autoStash
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
# Dedicated SSH host alias — avoids other ~/.ssh/config github.com keys winning.
GITHUB_SSH_HOST="github.com-ls-app"
LS_REPO_SSH="git@${GITHUB_SSH_HOST}:qmoxi/ls-app.git"
DEPLOY_KEY="${HOME}/.ssh/id_ed25519_ls_app_deploy"
DEPLOY_PUB="${DEPLOY_KEY}.pub"
GITHUB_KEYS_URL="https://github.com/qmoxi/ls-app/settings/keys"

log() { echo -e "\033[1;36m[ls-install]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ls-install]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ls-install]\033[0m $*" >&2; exit 1; }

configure_git_pull_policy() {
	command -v git >/dev/null 2>&1 || return 0
	git config --global pull.rebase true
	git config --global rebase.autoStash true
}

# GNOME Terminal → /dev/pts/N; use `tty` first, then /dev/tty.
resolve_user_tty() {
	local t=""
	t=$(tty 2>/dev/null || true)
	if [[ -n "${t}" && -r "${t}" ]]; then
		echo "${t}"
		return 0
	fi
	if [[ -r /dev/tty ]]; then
		echo /dev/tty
		return 0
	fi
	return 1
}

# curl | bash: script is on stdin, not the terminal. Re-download and exec bash -i on a script file.
ensure_interactive_shell() {
	if [[ -t 0 ]]; then
		return 0
	fi
	if [[ -n "${LS_INSTALL_REEXEC:-}" ]]; then
		die "Still non-interactive after re-exec (-t 0 false). Use:
  curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh"
	fi

	local user_tty script_tmp
	user_tty=$(resolve_user_tty) || die "No terminal device (run from GNOME Terminal on the desktop, not a non-TTY SSH session).

  curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh"

	script_tmp="$(mktemp /tmp/ls-install.XXXXXX.sh)"
	curl -fsSL "${INSTALL_SCRIPT_URL}" -o "${script_tmp}"
	chmod +x "${script_tmp}"

	echo "[ls-install] Attaching to ${user_tty} for interactive prompts…" >"${user_tty}"

	export LS_INSTALL_REEXEC=1
	export REPO_DIR LS_INSTALL_BRANCH LS_SKIP_DEPLOY_KEY_PROMPT
	exec env LS_INSTALL_REEXEC=1 REPO_DIR="${REPO_DIR}" LS_INSTALL_BRANCH="${LS_INSTALL_BRANCH}" \
		LS_SKIP_DEPLOY_KEY_PROMPT="${LS_SKIP_DEPLOY_KEY_PROMPT:-}" \
		bash -i "${script_tmp}" "$@" <"${user_tty}" >"${user_tty}" 2>&1
}

configure_ssh_for_ls_app() {
	local cfg="${HOME}/.ssh/config"
	mkdir -p "${HOME}/.ssh"
	touch "${cfg}"
	chmod 600 "${cfg}"
	if grep -q "Host ${GITHUB_SSH_HOST}" "${cfg}" 2>/dev/null; then
		return 0
	fi
	cat >>"${cfg}" <<EOF

Host ${GITHUB_SSH_HOST}
  HostName github.com
  User git
  IdentityFile ${DEPLOY_KEY}
  IdentitiesOnly yes
EOF
}

github_ssh_probe() {
	ssh -o BatchMode=yes -o ConnectTimeout=15 -T "git@${GITHUB_SSH_HOST}" 2>&1 || true
}

github_ssh_ok() {
	local out
	out="$(github_ssh_probe)"
	if echo "${out}" | grep -qiE 'successfully authenticated'; then
		return 0
	fi
	if echo "${out}" | grep -qiE 'Hi [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+!'; then
		return 0
	fi
	return 1
}

explain_github_ssh_failure() {
	local out
	out="$(github_ssh_probe)"
	warn "    ssh test: ${out}"
	warn "    deploy key file: ${DEPLOY_KEY}"
	warn "    fingerprint: $(ssh-keygen -lf "${DEPLOY_PUB}" 2>/dev/null | awk '{print $2}')"
	warn "    Add the pubkey printed above at ${GITHUB_KEYS_URL}"
	warn "    Repo must be qmoxi/ls-app (not ls-app-workspace-install). Enable Allow write access."
	warn "    A pubkey can only be one repo's deploy key on GitHub — if 'already in use', add THIS new key, not an old one."
}

prompt_user() {
	local msg="$1" user_tty=""
	user_tty=$(resolve_user_tty 2>/dev/null || true)
	if [[ -t 0 ]]; then
		read -rp "${msg}"
		return 0
	fi
	if [[ -n "${user_tty}" ]]; then
		read -rp "${msg}" <"${user_tty}"
		return 0
	fi
	return 1
}

wait_for_github_deploy_key() {
	local user_tty=""
	user_tty=$(resolve_user_tty 2>/dev/null || true)

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

	log "    Waiting until this key is saved on GitHub (press Enter to re-check)…"
	explain_github_ssh_failure

	while ! github_ssh_ok; do
		if [[ -t 0 ]]; then
			read -rp "Press Enter after the deploy key is saved on GitHub (Allow write access)... "
		elif [[ -n "${user_tty}" ]]; then
			read -rp "Press Enter after the deploy key is saved on GitHub (Allow write access)... " <"${user_tty}"
		else
			die "No terminal for prompts. Re-run: curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh"
		fi
		if ! github_ssh_ok; then
			explain_github_ssh_failure
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

One-liner (GNOME Terminal — auto re-attaches when piped):
  curl -fsSL ${INSTALL_SCRIPT_URL} | bash

Alternative (always interactive):
  bash -i <(curl -fsSL ${INSTALL_SCRIPT_URL})

Or download first:
  curl -fsSL ${INSTALL_SCRIPT_URL} -o install.sh && bash install.sh
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
configure_git_pull_policy
log "    git pull: rebase + autoStash (global)"

# ------------------------------------------------------------------------------
log "2/5 SSH deploy key"
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if [[ ! -f "${DEPLOY_KEY}" ]]; then
	ssh-keygen -t ed25519 -N "" -f "${DEPLOY_KEY}" -C "ls-workspace-$(hostname -s)"
fi
chmod 600 "${DEPLOY_KEY}"
chmod 644 "${DEPLOY_PUB}"

configure_ssh_for_ls_app

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
		git -C "${REPO_DIR}" pull --rebase --autostash --quiet || true
	fi
fi

BOOTSTRAP="${REPO_DIR}/infra/workspaces/bootstrap-workspace.sh"
[[ -x "${BOOTSTRAP}" || -f "${BOOTSTRAP}" ]] || die "Missing ${BOOTSTRAP} after clone"

# ------------------------------------------------------------------------------
log "5/5 Run bootstrap-workspace.sh"
export REPO_DIR
export REPO_URL="${LS_REPO_SSH}"
# Mirror WorkSpace paths (ls.tgz + tests/.env scp) — under /home/build, not /opt/build.
export LS_BUILD_DIR="${LS_BUILD_DIR:-/home/build}"
export LS_MIRROR_REMOTE_TGZ="${LS_MIRROR_REMOTE_TGZ:-${LS_BUILD_DIR}/ls.tgz}"
export LS_MIRROR_REPO="${LS_MIRROR_REPO:-${LS_BUILD_DIR}/ls-app}"
exec bash "${BOOTSTRAP}"
