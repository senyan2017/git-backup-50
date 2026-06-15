#!/bin/sh
#
# Restore a single git repository from its backup bundle files.
#
# Bundles created by backup-git.sh are looked up under a source directory in
# both supported layouts and applied oldest-first (the file name timestamp
# defines the order): the first bundle is cloned, the following ones are pulled.
#
# Usage: backup-git-restore.sh [OPTIONS] <restore_dir> <repo_name>
#   See --help for the full list of options and examples.
#

set -u

PROG=$(basename "$0")

usage() {
	cat <<EOF
Usage: $PROG [OPTIONS] <restore_dir> <repo_name>

Restore <repo_name> into <restore_dir>/<repo_name> from its bundle files.
Bundles are looked up under the source directory in both layouts:
  nested:  <source>/<repo_name>/<repo_name>_*.bundle
  flat:    <source>/<repo_name>_*.bundle
and applied in chronological order (by file name timestamp).

Options:
  -s, --source DIR   Directory that holds the bundle files (default: current dir).
      --dry-run      List the bundles that would be applied, in order, then exit.
  -h, --help         Show this help and exit.

Examples:
  # bundles in the current directory (run from inside the backup dir)
  $PROG /tmp/git repo

  # bundles under /backup, layout is auto-detected (nested or flat)
  $PROG --source /backup /tmp/git repo
EOF
}

# ----------------------------------------------------------------------------
# defaults / argument parsing
# ----------------------------------------------------------------------------
SOURCE_DIR="."
DRY_RUN="0"
POS1=""
POS2=""
POS_COUNT=0

while [ $# -gt 0 ]; do
	case "$1" in
		-s|--source)
			[ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
			SOURCE_DIR="$2"; shift 2 ;;
		--source=*) SOURCE_DIR="${1#*=}"; shift ;;
		--dry-run)  DRY_RUN="1"; shift ;;
		-h|--help)  usage; exit 0 ;;
		--)         shift; break ;;
		-*)         echo "ERROR: unknown option '$1'" >&2; usage >&2; exit 2 ;;
		*)
			POS_COUNT=$((POS_COUNT + 1))
			if   [ $POS_COUNT -eq 1 ]; then POS1="$1"
			elif [ $POS_COUNT -eq 2 ]; then POS2="$1"
			else echo "ERROR: too many arguments: '$1'" >&2; exit 2
			fi
			shift ;;
	esac
done
while [ $# -gt 0 ]; do
	POS_COUNT=$((POS_COUNT + 1))
	if   [ $POS_COUNT -eq 1 ]; then POS1="$1"
	elif [ $POS_COUNT -eq 2 ]; then POS2="$1"
	else echo "ERROR: too many arguments: '$1'" >&2; exit 2
	fi
	shift
done

if [ -z "$POS1" ] || [ -z "$POS2" ]; then
	echo "ERROR: <restore_dir> and <repo_name> are required" >&2
	usage >&2
	exit 2
fi

RESTORE_DIR="$POS1"
REPO="$POS2"
REPO_DIR="$RESTORE_DIR/$REPO"

# ----------------------------------------------------------------------------
# validation
# ----------------------------------------------------------------------------
if [ ! -d "$SOURCE_DIR" ]; then
	echo "ERROR: source directory '$SOURCE_DIR' does not exist" >&2
	exit 1
fi
if [ ! -r "$SOURCE_DIR" ]; then
	echo "ERROR: source directory '$SOURCE_DIR' is not readable (permission denied)" >&2
	exit 1
fi

# work with an absolute source directory so bundle paths stay valid even after
# git changes directory (git -C ...) while applying them.
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd) || {
	echo "ERROR: cannot access source directory '$SOURCE_DIR'" >&2
	exit 1
}

# ----------------------------------------------------------------------------
# collect bundles (nested + flat), ordered by file name (= timestamp)
# ----------------------------------------------------------------------------
TMP_LIST=$(mktemp 2>/dev/null) || TMP_LIST="/tmp/${PROG}.$$"
trap 'rm -f "$TMP_LIST"' EXIT INT TERM
: > "$TMP_LIST"
{
	ls -1 "$SOURCE_DIR/$REPO/${REPO}"_*.bundle 2>/dev/null
	ls -1 "$SOURCE_DIR/${REPO}"_*.bundle 2>/dev/null
} | awk -F/ '{ print $NF "\t" $0 }' | sort | cut -f2- > "$TMP_LIST"

count=$(wc -l < "$TMP_LIST" | tr -d ' ')
if [ "$count" -eq 0 ]; then
	echo "ERROR: no bundle files found for '$REPO' under '$SOURCE_DIR'" >&2
	echo "       looked for: $SOURCE_DIR/$REPO/${REPO}_*.bundle" >&2
	echo "              and: $SOURCE_DIR/${REPO}_*.bundle" >&2
	exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
	echo "INFO: DRY-RUN - would restore '$REPO' into '$REPO_DIR' from $count bundle(s):"
	i=0
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		i=$((i + 1))
		echo "  $i. $f"
	done < "$TMP_LIST"
	exit 0
fi

if [ -d "$REPO_DIR" ]; then
	echo "WARN: '$REPO_DIR' already exists - bundles will be pulled into it"
else
	if ! mkdir -p "$RESTORE_DIR" 2>/dev/null; then
		echo "ERROR: cannot create restore directory '$RESTORE_DIR' (permission denied?)" >&2
		exit 1
	fi
fi

# ----------------------------------------------------------------------------
# apply bundles
# ----------------------------------------------------------------------------
rc=1
while IFS= read -r bundleFile; do
	[ -n "$bundleFile" ] || continue

	if [ -d "$REPO_DIR" ]; then
		# repository already exists: verify the bundle against it, then pull
		echo "INFO: verifying bundle '$bundleFile' for '$REPO'"
		git -C "$REPO_DIR" bundle verify "$bundleFile"
		rc=$?
		if [ $rc -ne 0 ]; then
			echo "ERROR: verification failed for '$bundleFile' (rc=$rc)" >&2
			exit $rc
		fi

		echo "INFO: pulling from bundle '$bundleFile'"
		# a bundle records branch refs but not HEAD, so tell git which branch to
		# pull (the first branch contained in the bundle).
		prBranch=$(git -C "$REPO_DIR" bundle list-heads "$bundleFile" 2>/dev/null \
			| awk '$2 ~ /^refs\/heads\// { sub(/^refs\/heads\//, "", $2); print $2; exit }')
		if [ -n "$prBranch" ]; then
			git -C "$REPO_DIR" pull "$bundleFile" "$prBranch"
		else
			git -C "$REPO_DIR" pull "$bundleFile"
		fi
		rc=$?
		if [ $rc -ne 0 ]; then
			echo "ERROR: pull failed for '$bundleFile' (rc=$rc)" >&2
			exit $rc
		fi
	else
		# first bundle: clone it (the clone validates the bundle as well)
		echo "INFO: cloning '$REPO' from bundle '$bundleFile'"
		git clone "$bundleFile" "$REPO_DIR"
		rc=$?
		if [ $rc -ne 0 ]; then
			echo "ERROR: clone failed from '$bundleFile' (rc=$rc)" >&2
			exit $rc
		fi
	fi
done < "$TMP_LIST"

if [ $rc -eq 0 ]; then
	echo "INFO: repository '$REPO' restored successfully into '$REPO_DIR'"
	exit 0
else
	echo "ERROR: restoring '$REPO' failed (rc=$rc)" >&2
	exit $rc
fi
