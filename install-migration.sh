#!/usr/bin/env bash
#
# Full migration setup — tools + golden DB. Run AFTER install.sh.
#
#   aws sso login --profile ls-admin
#   bash scripts/workspaces/ls-workspace-install/install-migration.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[1;36m[ls-migration]\033[0m $*"; }

[[ "$(id -u)" -eq 0 ]] && { echo "Run as the WorkSpace user, not root." >&2; exit 1; }

log "── migration tools ──"
bash "${SCRIPT_DIR}/install-migration-tools.sh"

log "── golden DB ──"
bash "${SCRIPT_DIR}/install-golden-db.sh"

log "done — restart Cursor, then:"
log "  cd /home/build/ls-app && node cursor-migrate/preflight.mjs --mode golden --recover"
