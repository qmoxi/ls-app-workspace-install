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

log "3/4 prerequisites (AWS SSO + docker group)"
if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
	die "AWS SSO not active for ${AWS_PROFILE}. Run: aws sso login --profile ${AWS_PROFILE}"
fi

# Ensure docker group uses the BARE AD login (ls-admin5), never user@domain.
# install-golden-db used to require a working docker socket *before* setup-golden-zfs
# could add the user — that left fresh boxes stuck with no docker group membership.
BARE_USER="$(id -un)"
BARE_USER="${BARE_USER%%@*}"
if ! getent group docker >/dev/null 2>&1; then
	# Docker not installed yet — setup-golden-zfs.sh will install it + add the user.
	log "    docker not installed yet — setup will install CE + add ${BARE_USER}"
else
	while IFS= read -r member; do
		[[ -z "${member}" ]] && continue
		if [[ "${member}" == *"@"* ]]; then
			warn "    removing domain-qualified docker member: ${member}"
			sudo gpasswd -d "${member}" docker >/dev/null 2>&1 || true
		fi
	done < <(getent group docker | awk -F: '{print $4}' | tr ',' '\n')
	if ! getent group docker | awk -F: '{print $4}' | tr ',' '\n' | grep -qx "${BARE_USER}"; then
		log "    adding ${BARE_USER} (bare name) to docker group"
		sudo gpasswd -a "${BARE_USER}" docker
	fi
	sudo systemctl enable --now docker >/dev/null 2>&1 || true
	if ! docker info >/dev/null 2>&1 && ! sg docker -c 'docker info' >/dev/null 2>&1; then
		die "docker group updated for ${BARE_USER}, but this session cannot use the socket yet.
  Sign out of the WorkSpace and back in (or reboot), then re-run:
    bash ${REPO_DIR}/scripts/workspaces/ls-workspace-install/install-golden-db.sh
  Verify after login:  groups   # must include docker (not user@domain)"
	fi
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
