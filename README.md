git-backup
==========

Shell scripts for creating and restoring **incremental backups** of git repositories using `git bundle`.

Each backup only contains commits made since the previous one (tracked via a `lastBackup` tag),
so repeated runs produce small, fast bundles suitable for long-term archival.

Features
--------
- **Incremental backups** — only new commits since last backup
- **Multi-repo scanning** — backs up all git repositories found under a directory
- **Repository filtering** — backup only repos matching a name or glob pattern (`--repo`)
- **Branch control** — backup all branches or only specific ones (`--branch`)
- **Organized output** — bundles grouped per repo: `<backup_dir>/<repo_name>/…bundle`
- **Dry-run preview** — see what would be backed up without creating anything (`--dry-run`)
- **Pre-flight validation** — clear errors for non-git dirs, missing branches, permission issues
- **Flexible restore** — restore all or selected repos; list available backups (`--list`)
- **Backward compatible** — restore script also reads flat (legacy) bundle directories

Quick Start
-----------

### Backup all repos in a directory

```bash
# scan ~/projects for git repos, store bundles in ~/backup
src/backup-git.sh ~/projects ~/backup
```

Output layout:
```
~/backup/
  repoA/
    repoA_20250101-120000.bundle
    repoA_20250102-120000.bundle
  repoB/
    repoB_20250101-120000.bundle
```

### Preview before running

```bash
src/backup-git.sh --dry-run ~/projects ~/backup
```

Example output:
```
INFO: === DRY RUN — no bundles will be created ===
INFO: scanning for repositories in: /home/user/projects (depth 2)
INFO: [repoA] would create INCREMENTAL bundle: /home/user/backup/repoA/repoA_20250616-100000.bundle
INFO: [repoB] no changes since last backup — skipped
INFO: [repoC] would create FULL bundle: /home/user/backup/repoC/repoC_20250616-100000.bundle
INFO: === DRY RUN complete ===
```

### Backup only specific repos

```bash
# exact name
src/backup-git.sh --repo myapp ~/projects ~/backup

# glob pattern — all repos starting with "api-"
src/backup-git.sh --repo "api-*" ~/projects ~/backup

# multiple patterns
src/backup-git.sh --repo myapp --repo "lib-*" ~/projects ~/backup
```

### Backup specific branches

```bash
# only main and develop branches
src/backup-git.sh --branch main --branch develop ~/projects ~/backup
```

### Restore repositories

```bash
# list what's available in a backup directory
src/backup-git-restore.sh --list /tmp/restored ~/backup

# restore all repos
src/backup-git-restore.sh /tmp/restored ~/backup

# restore only "myapp"
src/backup-git-restore.sh --repo myapp /tmp/restored ~/backup
```

Usage Reference
---------------

### backup-git.sh

```
backup-git.sh [OPTIONS] <repository_dir> [<backup_dir>]

Arguments:
  repository_dir    Directory to scan for git repos (or a single repo path)
  backup_dir        Destination for bundles (default: ~/backup)

Options:
  -r, --repo PATTERN    Only backup repos matching PATTERN (repeatable; glob ok)
  -b, --branch BRANCH   Only include specific branch(es) (repeatable)
  -d, --depth N         Max search depth for .git dirs (default: 2)
  -n, --dry-run         Preview what would be backed up; create nothing
  -h, --help            Show help
```

### backup-git-restore.sh

```
backup-git-restore.sh [OPTIONS] <restore_dir> <backup_dir>

Arguments:
  restore_dir     Where to create restored repositories
  backup_dir      Directory containing backup bundles

Options:
  -r, --repo NAME     Restore only this repository
  -l, --list          List available repositories and exit
  -h, --help          Show help
```

Examples
--------

### Daily backup via cron

```bash
# crontab entry: backup all repos at 2 AM daily
0 2 * * * /path/to/backup-git.sh /home/user/projects /mnt/backup/git
```

### Backup a single repo

```bash
src/backup-git.sh /path/to/my-repo /mnt/backup/git
```

### Backup with branch filter and dry-run

```bash
src/backup-git.sh -b main -b release --dry-run ~/projects ~/backup
```

### Multiple repos with glob + branch filter

```bash
src/backup-git.sh --repo "api-*" --repo "web-*" -b main ~/projects ~/backup
```

### Restore and verify

```bash
# see what's available
src/backup-git-restore.sh --list /tmp/git ~/backup

# restore one repo
src/backup-git-restore.sh --repo myapp /tmp/git ~/backup

# check the result
git -C /tmp/git/myapp log --oneline
```

### Legacy flat layout

The restore script also reads bundles from a flat directory (no subdirectories):
```
~/backup/
  repoA_20250101-120000.bundle
  repoA_20250102-120000.bundle
  repoB_20250101-120000.bundle
```
Simply point the restore script at the flat directory — it auto-detects the layout.

How It Works
------------

1. The script scans `<repository_dir>` for `.git` directories (up to `--depth` levels).
2. For each repo, it checks for a `lastBackup` tag:
   - **No tag** → creates a full bundle of all branches (or selected branches).
   - **Tag exists** → creates an incremental bundle with only commits since the tag.
   - **No new commits** → skips the repo.
3. After a successful bundle, the `lastBackup` tag is updated to the latest commit.
4. Bundles are saved under `<backup_dir>/<repo_name>/` with timestamps.

Restore processes bundles in chronological order (oldest first), cloning from the
first bundle and pulling from subsequent ones.

Testing
-------

```bash
cd test
./run.sh
```

The test suite covers:
- Basic incremental backup and restore
- Dry-run mode (no files created)
- Repo name filtering (exact and glob patterns)
- Branch-specific backup
- Error handling (non-git dirs, missing branches, bad paths)
- Multi-repo backup and selective restore
- Restore `--list` mode
