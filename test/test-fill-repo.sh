#!/bin/sh
#
# test-fill-repo.sh - add one commit to a test repo and create a backup bundle.
#
# Usage: test-fill-repo.sh [<bundle_file>] [<repo_name>] [<src_dir>] [<backup_dir>]
#
# Steps:
#   1. Locate the backup script.
#   2. Clone the repo from the seed bundle if it doesn't exist yet.
#   3. Append a dummy change and commit it.
#   4. Run backup-git.sh to create an incremental bundle.
#

. "$(dirname "$0")/lib_test.sh"

# ── Arguments (override defaults from lib_test.sh) ────────────────────────────

SRC_BUNDLE="${1:-${TEST_BUNDLE}}"
REPO="${2:-${REPO_NAME}}"
GBACKUP_DIR="$(resolve_path "${3:-${GBACKUP_DIR}}")"
BACKUP_DIR="$(resolve_path "${4:-${BACKUP_DIR}}")"

# ── Step 1: Preconditions ─────────────────────────────────────────────────────

require_file "${GBACKUP_DIR}/backup-git.sh" "backup script"

[ -d "${BACKUP_DIR}" ] || mkdir -p "${BACKUP_DIR}"

# ── Step 2: Clone the seed repo if needed ─────────────────────────────────────

if [ ! -d "${REPO}" ]; then
	log_info "cloning seed repo from '${SRC_BUNDLE}' → '${REPO}'"
	git clone "${SRC_BUNDLE}" "${REPO}" || die "seed clone failed"
fi

# ── Step 3: Simulate a change ─────────────────────────────────────────────────

enter_dir "${REPO}"

echo "AAA" >> A
datetime="$(date +%Y%m%d-%H%M%S)"
git commit -am "changes ${datetime}" || die "test commit failed"

leave_dir

# ── Step 4: Run backup ────────────────────────────────────────────────────────

log_info "running backup-git.sh for '${REPO}'"
"${GBACKUP_DIR}/backup-git.sh" "${REPO}" "${BACKUP_DIR}" || die "backup failed"
