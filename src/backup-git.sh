#!/bin/sh
#
# Backup one or more git repositories using incremental git bundle files.
#
# Searches <repository_dir> for git repositories (directories that contain a
# ".git") and creates incremental bundle files containing the changes made
# since the last backup. A marker tag (default: "lastBackup") records the last
# commit that was already bundled, so the next run only exports new commits.
#
# The first backup of a repository is a full bundle of the selected branch(es);
# every following backup only contains the new commits (<tag>..<branch>).
#
# Usage: backup-git.sh [OPTIONS] <repository_dir> [<backup_dir>]
#   See --help for the full list of options and examples.
#

set -u

PROG=$(basename "$0")

usage() {
	cat <<EOF
Usage: $PROG [OPTIONS] <repository_dir> [<backup_dir>]

Search <repository_dir> for git repositories and create incremental bundle
files for each of them in <backup_dir> (default: \$HOME/backup).

Options:
  -n, --name PATTERN     Only back up repositories whose name matches PATTERN
                         (shell glob, e.g. 'web-*'). May be repeated; a repo is
                         backed up if it matches any pattern. Default: all repos.
  -b, --branch BRANCH    Branch to back up (default: master). May be repeated to
                         back up several branches.
  -l, --layout LAYOUT    How bundle files are organised under <backup_dir>:
                           nested  <backup_dir>/<repo>/<repo>_<ts>.bundle  (default)
                           flat    <backup_dir>/<repo>_<ts>.bundle
  -d, --depth N          Directory depth to search for repositories (default: 2).
  -t, --tag TAG          Name of the marker tag for the last backup
                         (default: lastBackup).
      --dry-run          Show which repositories and bundle files would be
                         created, without changing anything on disk.
  -h, --help             Show this help and exit.

Bundle file name pattern: <repo>_YYYYmmdd-HHMMSS.bundle

Examples:
  # Back up every repository found under ~/projects into /backup
  $PROG ~/projects /backup

  # Only repositories named "web-*", back up branch develop, preview first
  $PROG --name 'web-*' --branch develop --dry-run ~/projects /backup

  # Back up two branches of a single repository, flat layout
  $PROG --branch master --branch release --layout flat ~/projects/app /backup
EOF
}

# ----------------------------------------------------------------------------
# defaults
# ----------------------------------------------------------------------------
BACKUP_DIR_DEFAULT="$HOME/backup"
BRANCHES=""        # space separated, defaults to "master" below
NAME_PATTERNS=""   # space separated globs, empty => match all
LAYOUT="nested"
DEPTH="2"
BACKUP_TAG="lastBackup"
DRY_RUN="0"

POS1=""
POS2=""
POS_COUNT=0

# ----------------------------------------------------------------------------
# argument parsing
# ----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		-n|--name)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			NAME_PATTERNS="$NAME_PATTERNS $2"; shift 2 ;;
		--name=*)   NAME_PATTERNS="$NAME_PATTERNS ${1#*=}"; shift ;;
		-b|--branch)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			BRANCHES="$BRANCHES $2"; shift 2 ;;
		--branch=*) BRANCHES="$BRANCHES ${1#*=}"; shift ;;
		-l|--layout)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			LAYOUT="$2"; shift 2 ;;
		--layout=*) LAYOUT="${1#*=}"; shift ;;
		-d|--depth)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			DEPTH="$2"; shift 2 ;;
		--depth=*)  DEPTH="${1#*=}"; shift ;;
		-t|--tag)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			BACKUP_TAG="$2"; shift 2 ;;
		--tag=*)    BACKUP_TAG="${1#*=}"; shift ;;
		--dry-run)  DRY_RUN="1"; shift ;;
		-h|--help)  usage; exit 0 ;;
		--)         shift; break ;;
		-*)         echo "ERROR: unknown option '$1'" >&2; usage >&2; exit 2 ;;
		*)
			POS_COUNT=$((POS_COUNT + 1))
			if   [ $POS_COUNT -eq 1 ]; then POS1="$1"
			elif [ $POS_COUNT -eq 2 ]; then POS2="$1"
			else echo "ERROR: too many arguments: '$1'" >&2; usage >&2; exit 2
			fi
			shift ;;
	esac
done

# positionals after a literal --
while [ $# -gt 0 ]; do
	POS_COUNT=$((POS_COUNT + 1))
	if   [ $POS_COUNT -eq 1 ]; then POS1="$1"
	elif [ $POS_COUNT -eq 2 ]; then POS2="$1"
	else echo "ERROR: too many arguments: '$1'" >&2; exit 2
	fi
	shift
done

if [ -z "$POS1" ]; then
	echo "ERROR: <repository_dir> is required" >&2
	usage >&2
	exit 2
fi

BACKUP_REPOS_BASEDIR="$POS1"
BACKUP_DIR="${POS2:-$BACKUP_DIR_DEFAULT}"
[ -n "$BRANCHES" ] || BRANCHES="master"

case "$LAYOUT" in
	nested|flat) ;;
	*) echo "ERROR: invalid --layout '$LAYOUT' (use 'nested' or 'flat')" >&2; exit 2 ;;
esac

case "$DEPTH" in
	''|*[!0-9]*) echo "ERROR: --depth must be a positive integer (got '$DEPTH')" >&2; exit 2 ;;
esac

# ----------------------------------------------------------------------------
# top level validation
# ----------------------------------------------------------------------------
if [ ! -d "$BACKUP_REPOS_BASEDIR" ]; then
	echo "ERROR: repository_dir '$BACKUP_REPOS_BASEDIR' is not a directory" >&2
	exit 1
fi
if [ ! -r "$BACKUP_REPOS_BASEDIR" ]; then
	echo "ERROR: repository_dir '$BACKUP_REPOS_BASEDIR' is not readable (permission denied)" >&2
	exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
	if [ ! -d "$BACKUP_DIR" ]; then
		echo "WARN: backup_dir '$BACKUP_DIR' does not exist yet (required for a real run)" >&2
	elif [ ! -w "$BACKUP_DIR" ]; then
		echo "WARN: backup_dir '$BACKUP_DIR' is not writable (a real run would fail)" >&2
	fi
else
	if [ ! -d "$BACKUP_DIR" ]; then
		echo "ERROR: backup_dir '$BACKUP_DIR' does not exist" >&2
		exit 1
	fi
	if [ ! -w "$BACKUP_DIR" ]; then
		echo "ERROR: backup_dir '$BACKUP_DIR' is not writable (permission denied)" >&2
		exit 1
	fi
fi

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

# name_matches <repoName> -> 0 if it should be backed up
name_matches() {
	[ -z "$NAME_PATTERNS" ] && return 0
	for pat in $NAME_PATTERNS; do
		# shellcheck disable=SC2254  # glob match intended
		case "$1" in
			$pat) return 0 ;;
		esac
	done
	return 1
}

# make_bundle <repoRoot> <fileName> <ref...>
make_bundle() {
	rr="$1"; fn="$2"; shift 2
	git -C "$rr" bundle create "$fn" "$@"
}

# ----------------------------------------------------------------------------
# scan for repositories
# ----------------------------------------------------------------------------
TMP_LIST=$(mktemp 2>/dev/null) || TMP_LIST="/tmp/${PROG}.$$"
trap 'rm -f "$TMP_LIST"' EXIT INT TERM
: > "$TMP_LIST"
find "$BACKUP_REPOS_BASEDIR" -maxdepth "$DEPTH" -type d -name '.git' 2>/dev/null | sort > "$TMP_LIST"

MATCHED=0
PLANNED=0
BACKED_UP=0
SKIPPED=0
ERRORS=0

[ "$DRY_RUN" = "1" ] && echo "INFO: DRY-RUN - no bundles will be created"
echo "INFO: scanning '$BACKUP_REPOS_BASEDIR' (depth $DEPTH) -> '$BACKUP_DIR' [layout: $LAYOUT, branches:$BRANCHES]"

while IFS= read -r repoGitDir; do
	[ -n "$repoGitDir" ] || continue
	repoRoot=$(dirname "$repoGitDir")
	repoName=$(basename "$repoRoot")

	name_matches "$repoName" || continue
	MATCHED=$((MATCHED + 1))

	# is this really a git repository?
	if ! git -C "$repoRoot" rev-parse --git-dir >/dev/null 2>&1; then
		echo "ERROR: '$repoRoot' is not a valid git repository - skipping"
		ERRORS=$((ERRORS + 1)); continue
	fi

	# do all requested branches exist?
	missing=""
	for br in $BRANCHES; do
		git -C "$repoRoot" show-ref --verify --quiet "refs/heads/$br" || missing="$missing $br"
	done
	if [ -n "$missing" ]; then
		echo "ERROR: $repoName: branch(es) not found:$missing - skipping"
		ERRORS=$((ERRORS + 1)); continue
	fi

	datetime=$(date +%Y%m%d-%H%M%S)
	if [ "$LAYOUT" = "nested" ]; then
		outDir="$BACKUP_DIR/$repoName"
	else
		outDir="$BACKUP_DIR"
	fi
	fileName="$outDir/${repoName}_${datetime}.bundle"

	# decide initial vs incremental
	if git -C "$repoRoot" rev-parse -q --verify "refs/tags/$BACKUP_TAG" >/dev/null 2>&1; then
		mode="incremental"
		total=0
		for br in $BRANCHES; do
			c=$(git -C "$repoRoot" rev-list --count "${BACKUP_TAG}..${br}" 2>/dev/null || echo 0)
			total=$((total + c))
		done
		if [ "$total" -eq 0 ]; then
			echo "INFO: $repoName: no changes since last backup - skipping"
			SKIPPED=$((SKIPPED + 1)); continue
		fi
	else
		mode="initial"
	fi

	if [ "$DRY_RUN" = "1" ]; then
		echo "PLAN: $repoName [$mode] -> $fileName (branches:$BRANCHES)"
		PLANNED=$((PLANNED + 1)); continue
	fi

	# make sure the output directory exists
	if [ ! -d "$outDir" ]; then
		if ! mkdir -p "$outDir" 2>/dev/null; then
			echo "ERROR: $repoName: cannot create output directory '$outDir' (permission denied?) - skipping"
			ERRORS=$((ERRORS + 1)); continue
		fi
	fi

	echo "INFO: $repoName: creating $mode bundle -> $fileName"
	if [ "$mode" = "initial" ]; then
		make_bundle "$repoRoot" "$fileName" $BRANCHES
		rc=$?
	else
		set --
		for br in $BRANCHES; do set -- "$@" "${BACKUP_TAG}..${br}"; done
		make_bundle "$repoRoot" "$fileName" "$@"
		rc=$?
	fi
	if [ $rc -ne 0 ]; then
		echo "ERROR: $repoName: bundle creation failed (rc=$rc)"
		rm -f "$fileName" 2>/dev/null
		ERRORS=$((ERRORS + 1)); continue
	fi

	if ! git -C "$repoRoot" bundle verify "$fileName" >/dev/null 2>&1; then
		echo "ERROR: $repoName: bundle verification failed for '$fileName'"
		ERRORS=$((ERRORS + 1)); continue
	fi

	# advance the marker tag to the primary (first) branch
	set -- $BRANCHES
	primary="$1"
	if ! git -C "$repoRoot" tag -f "$BACKUP_TAG" "$primary" >/dev/null 2>&1; then
		echo "WARN: $repoName: could not update marker tag '$BACKUP_TAG'"
	fi

	echo "INFO: $repoName: done ($fileName)"
	BACKED_UP=$((BACKED_UP + 1))
done < "$TMP_LIST"

# ----------------------------------------------------------------------------
# summary
# ----------------------------------------------------------------------------
echo "----"
if [ "$DRY_RUN" = "1" ]; then
	echo "INFO: dry-run summary: matched=$MATCHED, would-backup=$PLANNED, skipped(no-change)=$SKIPPED, errors=$ERRORS"
else
	echo "INFO: summary: matched=$MATCHED, backed-up=$BACKED_UP, skipped(no-change)=$SKIPPED, errors=$ERRORS"
fi

if [ "$MATCHED" -eq 0 ]; then
	echo "WARN: no repositories matched under '$BACKUP_REPOS_BASEDIR'" >&2
fi

[ "$ERRORS" -eq 0 ] || exit 1
exit 0
