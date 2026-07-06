#!/usr/bin/env bash
#
# Golden DB setup — run AFTER install-migration-tools.sh.
# Requires: aws sso login --profile ls-admin
#
#   bash infra/workspaces/ls-workspace-install/install-golden-db.sh

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/build/ls-app}"
AWS_PROFILE="${AWS_PROFILE:-ls-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${LOCAL_REPO}/infra/workspaces/setup-migration-workspace.sh" ]]; then
	REPO_DIR="${LOCAL_REPO}"
fi

log() { echo -e "\033[1;36m[ls-golden-db]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ls-golden-db]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ls-golden-db]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] && die "Run as the WorkSpace user, not root."

log "1/3 verify ls-app"
[[ -d "${REPO_DIR}/.git" ]] || die "Missing ${REPO_DIR} — run install.sh first."

log "2/3 pull latest ls-app"
git -C "${REPO_DIR}" fetch --all --tags --quiet
if [[ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
	git -C "${REPO_DIR}" pull --rebase --autostash --quiet || true
fi

SETUP="${REPO_DIR}/infra/workspaces/setup-migration-workspace.sh"
[[ -f "${SETUP}" ]] || die "Missing ${SETUP}"

if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
	warn "AWS SSO not active for ${AWS_PROFILE}."
	warn "Run: aws sso login --profile ${AWS_PROFILE}"
	exit 1
fi

log "3/3 golden DB (Docker + ZFS + base@T seed)"
export REPO_DIR AWS_PROFILE
exec bash "${SETUP}" --db-only
