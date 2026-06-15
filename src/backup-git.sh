#!/bin/sh
#
# backup-git.sh - Backup git repositories using incremental bundle files.
#
# Searches for git repositories inside the given directory and creates
# incremental bundle files containing changes since the last backup.
# The tag "lastBackup" marks the last commit included in a bundle.
#
# Bundles are organized per-repository:
#   <backup_dir>/<repo_name>/<repo_name>_YYYYmmdd-HHMMSS.bundle
#
# Usage: backup-git.sh [OPTIONS] <repository_dir> [<backup_dir>]
#

set -e

# ── defaults ──────────────────────────────────────────────────────────
BACKUP_TAG="lastBackup"
MAX_DEPTH=2
DRY_RUN=0
ALL_BRANCHES=1
BRANCHES=""
REPO_FILTERS=""
REPO_DIR=""
BACKUP_DIR=""

# ── helpers ───────────────────────────────────────────────────────────
usage() {
	cat <<'EOF'
Usage: backup-git.sh [OPTIONS] <repository_dir> [<backup_dir>]

Backup git repositories as incremental bundle files.

Arguments:
  repository_dir    Directory to scan for git repositories (or a single repo)
  backup_dir        Destination for bundles (default: ~/backup)

Options:
  -r, --repo PATTERN    Only backup repos matching PATTERN (repeatable; glob ok)
  -b, --branch BRANCH   Only include specific branch(es) (repeatable)
  -d, --depth N         Max search depth for .git dirs (default: 2)
  -n, --dry-run         Preview what would be backed up; create nothing
  -h, --help            Show this help message

Output layout:
  <backup_dir>/<repo_name>/<repo_name>_YYYYmmdd-HHMMSS.bundle

Examples:
  # Backup all repos under ~/projects
  backup-git.sh ~/projects ~/backup

  # Dry-run: see what would be backed up
  backup-git.sh --dry-run ~/projects ~/backup

  # Backup only repos whose name starts with "api-"
  backup-git.sh --repo "api-*" ~/projects ~/backup

  # Backup only main and develop branches
  backup-git.sh -b main -b develop ~/projects ~/backup

  # Combine filters
  backup-git.sh -r myapp -b main -n ~/projects ~/backup
EOF
}

log_info()  { echo "INFO: $*"; }
log_warn()  { echo "WARN: $*" >&2; }
log_error() { echo "ERROR: $*" >&2; }

die() { log_error "$*"; exit 1; }

# ── argument parsing ──────────────────────────────────────────────────
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage; exit 0 ;;
		-n|--dry-run)
			DRY_RUN=1; shift ;;
		-r|--repo)
			[ $# -ge 2 ] || die "option $1 requires a value"
			REPO_FILTERS="${REPO_FILTERS}${REPO_FILTERS:+ }$2"
			ALL_BRANCHES_KEEP=1  # just consumed; nothing else
			shift 2 ;;
		-b|--branch)
			[ $# -ge 2 ] || die "option $1 requires a value"
			ALL_BRANCHES=0
			BRANCHES="${BRANCHES}${BRANCHES:+ }$2"
			shift 2 ;;
		-d|--depth)
			[ $# -ge 2 ] || die "option $1 requires a value"
			MAX_DEPTH="$2"; shift 2 ;;
		--)
			shift; break ;;
		-*)
			die "unknown option: $1 (try --help)" ;;
		*)
			# positional arguments
			if [ -z "${REPO_DIR}" ]; then
				REPO_DIR="$1"
			elif [ -z "${BACKUP_DIR}" ]; then
				BACKUP_DIR="$1"
			else
				die "unexpected argument: $1"
			fi
			shift ;;
	esac
done

# ── validate positional args ──────────────────────────────────────────
[ -n "${REPO_DIR}" ]  || { usage; exit 1; }
BACKUP_DIR="${BACKUP_DIR:-$HOME/backup}"

# resolve to absolute paths
REPO_DIR="$(readlink -f "${REPO_DIR}" 2>/dev/null || echo "${REPO_DIR}")"
BACKUP_DIR="$(readlink -f "${BACKUP_DIR}" 2>/dev/null || echo "${BACKUP_DIR}")"

# ── pre-flight checks ────────────────────────────────────────────────
if [ ! -d "${REPO_DIR}" ]; then
	die "repository directory does not exist: ${REPO_DIR}"
fi

if [ ! -r "${REPO_DIR}" ]; then
	die "cannot read repository directory: ${REPO_DIR}"
fi

# create backup dir unless dry-run
if [ "${DRY_RUN}" -eq 0 ]; then
	if [ ! -d "${BACKUP_DIR}" ]; then
		mkdir -p "${BACKUP_DIR}" || die "cannot create backup directory: ${BACKUP_DIR}"
	fi
	if [ ! -w "${BACKUP_DIR}" ]; then
		die "backup directory is not writable: ${BACKUP_DIR}"
	fi
fi

if [ "${DRY_RUN}" -eq 1 ]; then
	log_info "=== DRY RUN — no bundles will be created ==="
fi

log_info "scanning for repositories in: ${REPO_DIR} (depth ${MAX_DEPTH})"
log_info "backup destination: ${BACKUP_DIR}"

if [ "${ALL_BRANCHES}" -eq 0 ]; then
	log_info "branches to backup: ${BRANCHES}"
fi

if [ -n "${REPO_FILTERS}" ]; then
	log_info "repo filters: ${REPO_FILTERS}"
fi

# ── helper: does repo name match any filter? ─────────────────────────
repo_matches_filter() {
	_name="$1"
	# no filter → matches everything
	[ -z "${REPO_FILTERS}" ] && return 0
	for _pat in ${REPO_FILTERS}; do
		case "${_name}" in
			${_pat}) return 0 ;;
		esac
	done
	return 1
}

# ── helper: validate branches exist in repo ──────────────────────────
validate_branches() {
	_repo_path="$1"
	_old_dir="$(pwd)"
	cd "${_repo_path}"
	for _br in ${BRANCHES}; do
		if ! git rev-parse --verify "${_br}" >/dev/null 2>&1; then
			cd "${_old_dir}"
			log_error "branch '${_br}' does not exist in $(basename "${_repo_path}")"
			return 1
		fi
	done
	cd "${_old_dir}"
	return 0
}

# ── helper: default branch of a repo ─────────────────────────────────
get_default_branch() {
	_repo_path="$1"
	_old_dir="$(pwd)"
	cd "${_repo_path}"
	# try symbolic-ref first (works for non-bare repos)
	_def="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
	if [ -z "${_def}" ]; then
		# fallback: first branch
		_def="$(git branch --format='%(refname:short)' | head -n1)"
	fi
	cd "${_old_dir}"
	echo "${_def}"
}

# ── discover and process repositories ────────────────────────────────
REPOS_FOUND=0
REPOS_BACKED=0
REPOS_SKIPPED=0

find "${REPO_DIR}" -maxdepth "${MAX_DEPTH}" -type d -name '.git' 2>/dev/null | sort | while read -r gitDir
do
	repoDir="$(dirname "${gitDir}")"
	repoName="$(basename "${repoDir}")"

	# ── filter ────────────────────────────────────────────────────
	if ! repo_matches_filter "${repoName}"; then
		continue
	fi

	REPOS_FOUND=$((REPOS_FOUND + 1))

	# ── pre-flight: is it actually a git repo? ────────────────────
	if ! git -C "${repoDir}" rev-parse --git-dir >/dev/null 2>&1; then
		log_warn "skipping ${repoName}: not a valid git repository"
		REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
		continue
	fi

	# ── determine branches to back up ─────────────────────────────
	if [ "${ALL_BRANCHES}" -eq 1 ]; then
		branch_args="--all"
		default_branch="$(get_default_branch "${repoDir}")"
	else
		# validate requested branches
		if ! validate_branches "${repoDir}"; then
			REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
			continue
		fi
		branch_args="${BRANCHES}"
		default_branch="$(echo "${BRANCHES}" | awk '{print $1}')"
	fi

	# ── build bundle arguments ────────────────────────────────────
	oldDir="$(pwd)"
	cd "${repoDir}"

	has_tag=0
	if git tag | grep -qx "${BACKUP_TAG}"; then
		has_tag=1
	fi

	if [ "${has_tag}" -eq 1 ]; then
		# check if there are new commits since last backup
		if [ "${ALL_BRANCHES}" -eq 1 ]; then
			new_commits="$(git log "${BACKUP_TAG}".."${default_branch}" --oneline 2>/dev/null | wc -l)"
		else
			new_commits=0
			for _br in ${BRANCHES}; do
				_cnt="$(git log "${BACKUP_TAG}".."${_br}" --oneline 2>/dev/null | wc -l)"
				new_commits=$((new_commits + _cnt))
			done
		fi

		if [ "${new_commits}" -eq 0 ]; then
			log_info "[${repoName}] no changes since last backup — skipped"
			cd "${oldDir}"
			REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
			continue
		fi

		# incremental: commits since lastBackup
		if [ "${ALL_BRANCHES}" -eq 1 ]; then
			bundle_rev_args="--all ${BACKUP_TAG}..${default_branch}"
		else
			bundle_rev_args=""
			for _br in ${BRANCHES}; do
				bundle_rev_args="${bundle_rev_args} ${_br} ${BACKUP_TAG}..${_br}"
			done
		fi
	else
		# initial full bundle
		if [ "${ALL_BRANCHES}" -eq 1 ]; then
			bundle_rev_args="--all"
		else
			bundle_rev_args="${BRANCHES}"
		fi
	fi

	# ── output path ───────────────────────────────────────────────
	repo_backup_dir="${BACKUP_DIR}/${repoName}"
	datetime="$(date +%Y%m%d-%H%M%S)"
	fileName="${repo_backup_dir}/${repoName}_${datetime}.bundle"

	if [ "${DRY_RUN}" -eq 1 ]; then
		if [ "${has_tag}" -eq 1 ]; then
			log_info "[${repoName}] would create INCREMENTAL bundle: ${fileName}"
		else
			log_info "[${repoName}] would create FULL bundle: ${fileName}"
		fi
		if [ "${ALL_BRANCHES}" -eq 0 ]; then
			log_info "[${repoName}]   branches: ${BRANCHES}"
		fi
		cd "${oldDir}"
		REPOS_BACKED=$((REPOS_BACKED + 1))
		continue
	fi

	# ── create bundle ─────────────────────────────────────────────
	mkdir -p "${repo_backup_dir}" || {
		log_error "[${repoName}] cannot create directory: ${repo_backup_dir}"
		cd "${oldDir}"
		REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
		continue
	}

	if [ "${has_tag}" -eq 1 ]; then
		log_info "[${repoName}] creating incremental bundle (${BACKUP_TAG}..${default_branch})"
	else
		log_info "[${repoName}] creating full bundle"
	fi
	log_info "[${repoName}] → ${fileName}"

	# shellcheck disable=SC2086
	if ! git bundle create "${fileName}" ${bundle_rev_args}; then
		log_error "[${repoName}] bundle creation failed"
		cd "${oldDir}"
		REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
		continue
	fi

	# verify
	if ! git bundle verify "${fileName}" >/dev/null 2>&1; then
		log_error "[${repoName}] bundle verification failed: ${fileName}"
		rm -f "${fileName}"
		cd "${oldDir}"
		REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
		continue
	fi

	# update tag
	git tag -f "${BACKUP_TAG}" "${default_branch}" >/dev/null 2>&1 || {
		log_warn "[${repoName}] failed to update tag '${BACKUP_TAG}'"
	}

	log_info "[${repoName}] done"
	REPOS_BACKED=$((REPOS_BACKED + 1))
	cd "${oldDir}"
done

if [ "${DRY_RUN}" -eq 1 ]; then
	log_info "=== DRY RUN complete ==="
fi
