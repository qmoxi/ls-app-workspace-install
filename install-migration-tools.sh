#!/usr/bin/env bash
#
# Migration tools setup — run AFTER install.sh on WorkSpaces that will golden-migrate.
# Canonical copy lives here; published to qmoxi/ls-app-workspace-install.
#
# From ls-app (after git pull):
#   bash infra/workspaces/ls-workspace-install/install-migration-tools.sh
#
# Public one-liner (after workspace-install repo is updated):
#   curl -fsSL --proto '=https' --tlsv1.2 \
#     https://raw.githubusercontent.com/qmoxi/ls-app-workspace-install/main/install-migration-tools.sh | bash

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/build/ls-app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When this file lives under ls-app/infra/workspaces/ls-workspace-install/, prefer local impl.
LOCAL_REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${LOCAL_REPO}/infra/workspaces/setup-migration-workspace.sh" ]]; then
	REPO_DIR="${LOCAL_REPO}"
fi

log() { echo -e "\033[1;36m[ls-migration-tools]\033[0m $*"; }
die() { echo -e "\033[1;31m[ls-migration-tools]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] && die "Run as the WorkSpace user, not root."

log "1/2 verify ls-app (run install.sh first if missing)"
[[ -d "${REPO_DIR}/.git" ]] || die "Missing ${REPO_DIR} — run install.sh first."

log "2/2 pull latest ls-app + migration tools setup"
git -C "${REPO_DIR}" fetch --all --tags --quiet
if [[ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
	git -C "${REPO_DIR}" pull --rebase --autostash --quiet || true
fi

SETUP="${REPO_DIR}/infra/workspaces/setup-migration-workspace.sh"
[[ -f "${SETUP}" ]] || die "Missing ${SETUP} — git pull ls-app main"

export REPO_DIR
exec bash "${SETUP}" --tools-only
