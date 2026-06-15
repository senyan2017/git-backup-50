#!/bin/sh
#
# backup-git-restore.sh - Restore git repositories from bundle files.
#
# Supports both the new organized layout:
#   <backup_dir>/<repo_name>/<repo_name>_*.bundle
# and the legacy flat layout:
#   <backup_dir>/<repo_name>_*.bundle
#
# Usage: backup-git-restore.sh [OPTIONS] <restore_dir> <backup_dir>
#

set -e

# ── defaults ──────────────────────────────────────────────────────────
RESTORE_DIR=""
BACKUP_DIR=""
REPO_NAME=""
LIST_ONLY=0

# ── helpers ───────────────────────────────────────────────────────────
usage() {
	cat <<'EOF'
Usage: backup-git-restore.sh [OPTIONS] <restore_dir> <backup_dir>

Restore git repositories from bundle files created by backup-git.sh.

Arguments:
  restore_dir     Directory where repositories will be restored
  backup_dir      Directory containing backup bundles

Options:
  -r, --repo NAME     Restore only the named repository
  -l, --list          List available repositories and exit
  -h, --help          Show this help message

Bundle layouts supported:
  Organized : <backup_dir>/<repo_name>/<repo_name>_*.bundle
  Legacy    : <backup_dir>/<repo_name>_*.bundle  (flat directory)

Examples:
  # List all restorable repositories
  backup-git-restore.sh --list /tmp/git ~/backup

  # Restore all repositories
  backup-git-restore.sh /tmp/git ~/backup

  # Restore only "myapp"
  backup-git-restore.sh --repo myapp /tmp/git ~/backup
EOF
}

log_info()  { echo "INFO: $*"; }
log_warn()  { echo "WARN: $*" >&2; }
log_error() { echo "ERROR: $*" >&2; }
die()       { log_error "$*"; exit 1; }

# ── argument parsing ──────────────────────────────────────────────────
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage; exit 0 ;;
		-r|--repo)
			[ $# -ge 2 ] || die "option $1 requires a value"
			REPO_NAME="$2"; shift 2 ;;
		-l|--list)
			LIST_ONLY=1; shift ;;
		--)
			shift; break ;;
		-*)
			die "unknown option: $1 (try --help)" ;;
		*)
			if [ -z "${RESTORE_DIR}" ]; then
				RESTORE_DIR="$1"
			elif [ -z "${BACKUP_DIR}" ]; then
				BACKUP_DIR="$1"
			else
				die "unexpected argument: $1"
			fi
			shift ;;
	esac
done

# ── validate ──────────────────────────────────────────────────────────
[ -n "${RESTORE_DIR}" ] || { usage; exit 1; }
[ -n "${BACKUP_DIR}" ]  || { usage; exit 1; }

if [ ! -d "${BACKUP_DIR}" ]; then
	die "backup directory does not exist: ${BACKUP_DIR}"
fi

# ── discover repos ────────────────────────────────────────────────────
# Collect unique repo names from both organized and flat layouts.
discover_repos() {
	_repos=""

	# organized: <backup_dir>/<repo_name>/<repo_name>_*.bundle
	for _dir in "${BACKUP_DIR}"/*/; do
		[ -d "${_dir}" ] || continue
		_rname="$(basename "${_dir}")"
		# check that it actually contains bundles for this name
		_count=$(find "${_dir}" -maxdepth 1 -name "${_rname}_*.bundle" 2>/dev/null | wc -l)
		if [ "${_count}" -gt 0 ]; then
			_repos="${_repos}${_repos:+ }${_rname}"
		fi
	done

	# flat: <backup_dir>/<repo_name>_*.bundle
	for _f in "${BACKUP_DIR}"/*_*.bundle; do
		[ -f "${_f}" ] || continue
		_base="$(basename "${_f}")"
		# strip timestamp suffix: <name>_YYYYmmdd-HHMMSS.bundle
		_rname="$(echo "${_base}" | sed 's/_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]\.bundle$//')"
		# skip if already found via organized layout
		case " ${_repos} " in
			*" ${_rname} "*) ;;
			*) _repos="${_repos}${_repos:+ }${_rname}" ;;
		esac
	done

	echo "${_repos}"
}

# get sorted bundle files for a repo (oldest first by name → timestamp)
get_bundles_for_repo() {
	_rname="$1"
	_files=""

	# organized layout
	_org_dir="${BACKUP_DIR}/${_rname}"
	if [ -d "${_org_dir}" ]; then
		_files="$(find "${_org_dir}" -maxdepth 1 -name "${_rname}_*.bundle" 2>/dev/null | sort)"
	fi

	# flat layout (only if nothing found in organized)
	if [ -z "${_files}" ]; then
		_files="$(find "${BACKUP_DIR}" -maxdepth 1 -name "${_rname}_*.bundle" 2>/dev/null | sort)"
	fi

	echo "${_files}"
}

ALL_REPOS="$(discover_repos)"

if [ -z "${ALL_REPOS}" ]; then
	die "no bundle files found in: ${BACKUP_DIR}"
fi

# ── filter to requested repo ──────────────────────────────────────────
if [ -n "${REPO_NAME}" ]; then
	found=0
	for _r in ${ALL_REPOS}; do
		if [ "${_r}" = "${REPO_NAME}" ]; then
			found=1; break
		fi
	done
	if [ "${found}" -eq 0 ]; then
		die "repository '${REPO_NAME}' not found in backup. Available: ${ALL_REPOS}"
	fi
	TARGET_REPOS="${REPO_NAME}"
else
	TARGET_REPOS="${ALL_REPOS}"
fi

# ── list mode ─────────────────────────────────────────────────────────
if [ "${LIST_ONLY}" -eq 1 ]; then
	echo "Repositories available in ${BACKUP_DIR}:"
	for _r in ${TARGET_REPOS}; do
		_bundles="$(get_bundles_for_repo "${_r}")"
		_count="$(echo "${_bundles}" | grep -c . || true)"
		echo "  ${_r}  (${_count} bundle(s))"
	done
	exit 0
fi

# ── restore ───────────────────────────────────────────────────────────
mkdir -p "${RESTORE_DIR}" || die "cannot create restore directory: ${RESTORE_DIR}"

rc_total=0
for repoName in ${TARGET_REPOS}; do
	repoDir="${RESTORE_DIR}/${repoName}"

	bundles="$(get_bundles_for_repo "${repoName}")"
	if [ -z "${bundles}" ]; then
		log_warn "[${repoName}] no bundles found — skipped"
		rc_total=1
		continue
	fi

	log_info "[${repoName}] restoring to ${repoDir}"

	echo "${bundles}" | while read -r bundleFile; do
		[ -n "${bundleFile}" ] || continue
		bundleBase="$(basename "${bundleFile}")"

		if [ -d "${repoDir}" ]; then
			# repo exists → verify and pull
			log_info "[${repoName}] verifying ${bundleBase}"
			if ! git -C "${repoDir}" bundle verify "${bundleFile}" >/dev/null 2>&1; then
				log_error "[${repoName}] verification failed for ${bundleBase}"
				exit 1
			fi

			log_info "[${repoName}] pulling from ${bundleBase}"
			if ! git -C "${repoDir}" pull "${bundleFile}" >/dev/null 2>&1; then
				log_error "[${repoName}] pull failed for ${bundleBase}"
				exit 1
			fi
		else
			# first bundle → clone
			log_info "[${repoName}] cloning from ${bundleBase}"
			if ! git bundle verify "${bundleFile}" >/dev/null 2>&1; then
				log_error "[${repoName}] initial verification failed for ${bundleBase}"
				exit 1
			fi
			if ! git clone "${bundleFile}" "${repoDir}" >/dev/null 2>&1; then
				log_error "[${repoName}] clone failed from ${bundleBase}"
				exit 1
			fi
		fi
	done

	if [ $? -eq 0 ]; then
		log_info "[${repoName}] restored successfully"
	else
		log_error "[${repoName}] restore failed"
		rc_total=1
	fi
done

if [ "${rc_total}" -eq 0 ]; then
	log_info "all repositories restored successfully"
else
	log_error "some repositories failed to restore"
	exit 1
fi
