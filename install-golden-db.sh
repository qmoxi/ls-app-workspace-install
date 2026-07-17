#!/usr/bin/env bash
#
# Golden DB setup — run AFTER install-migration-tools.sh.
# Requires: aws sso login --profile ls-admin
# May require: sign out/in after first Docker install (docker group activation)
#
#   bash scripts/workspaces/ls-workspace-install/install-golden-db.sh

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/build/ls-app}"
AWS_PROFILE="${AWS_PROFILE:-ls-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${LOCAL_REPO}/scripts/workspaces/setup-migration-workspace.sh" ]]; then
	REPO_DIR="${LOCAL_REPO}"
fi

log() { echo -e "\033[1;36m[ls-golden-db]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ls-golden-db]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ls-golden-db]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] && die "Run as the WorkSpace user, not root."

log "1/4 verify ls-app"
[[ -d "${REPO_DIR}/.git" ]] || die "Missing ${REPO_DIR} — run install.sh first."

log "2/4 pull latest ls-app (required — installer bugfixes live in this repo)"
git -C "${REPO_DIR}" fetch --all --tags --quiet
if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
	warn "    working tree dirty — stashing local changes before pull"
fi
git -C "${REPO_DIR}" pull --rebase --autostash --quiet \
	|| die "git pull failed in ${REPO_DIR} — resolve and re-run"
log "    ls-app @ $(git -C "${REPO_DIR}" rev-parse --short HEAD)"

SETUP="${REPO_DIR}/scripts/workspaces/setup-migration-workspace.sh"
[[ -f "${SETUP}" ]] || die "Missing ${SETUP}"

log "3/4 prerequisites (AWS SSO + docker)"
if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
	die "AWS SSO not active for ${AWS_PROFILE}. Run: aws sso login --profile ${AWS_PROFILE}"
fi
if ! docker info >/dev/null 2>&1 && ! sg docker -c 'docker info' >/dev/null 2>&1; then
	die "docker socket not accessible in this session.
  If Docker was just installed, sign out of the WorkSpace and back in (or: newgrp docker), then re-run this script."
fi

log "4/4 golden DB (Docker + ZFS + base@T seed — first run may take 10–30 min)"
export REPO_DIR AWS_PROFILE
bash "${SETUP}" --db-only

if ! sudo zfs list -H -o name "tank/lsgold/base@T" >/dev/null 2>&1; then
	die "install finished but tank/lsgold/base@T is missing — ZFS fast reset is NOT enabled.
  Diagnostics:
    sudo zfs list -r tank/lsgold
    docker images | grep -i mysql
  Retry: FORCE=1 bash ${REPO_DIR}/scripts/workspaces/setup-golden-zfs.sh"
fi

log "✓ golden DB ready: tank/lsgold/base@T (ZFS fast reset enabled)"
log "  verify: bash ${REPO_DIR}/cursor-migrate/db-container.sh status --scenario scheduler-UrgentLog"
