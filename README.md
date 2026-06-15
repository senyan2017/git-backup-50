git-backup
==========
Shell scripts for creating and restoring incremental backups of git
repositories using git bundles.

Each repository is exported with `git bundle`. The first backup of a repository
is a **full** bundle of the selected branch(es); every following backup only
contains the commits added since the previous run. A marker tag (default:
`lastBackup`) records the last commit that was already bundled.

Both scripts are plain POSIX `/bin/sh` and only depend on `git`.

Highlights
----------
* Back up a single repository or scan a directory for many repositories.
* Pick which repositories to back up by name (`--name`, glob, repeatable).
* Pick which branch(es) to back up (`--branch`, repeatable, default `master`).
* Two output layouts: `nested` (one sub-directory per repository, the default,
  good for long-term archives) and `flat` (everything in one directory).
* Preview what would happen with `--dry-run` before touching the disk.
* Up-front checks (not a git repository, missing branch, unwritable
  destination, ...) with explicit error messages.
* The restore script auto-detects both layouts.

Backup
----------
```
backup-git.sh [OPTIONS] <repository_dir> [<backup_dir>]
```
`<backup_dir>` defaults to `$HOME/backup`. Bundle files are named
`<repo>_YYYYmmdd-HHMMSS.bundle`.

Options:

| Option | Description |
| ------ | ----------- |
| `-n, --name PATTERN` | Only back up repositories whose name matches PATTERN (shell glob, e.g. `web-*`). May be repeated. Default: all repositories. |
| `-b, --branch BRANCH` | Branch to back up (default: `master`). May be repeated to back up several branches. |
| `-l, --layout LAYOUT` | `nested` → `<backup_dir>/<repo>/<repo>_<ts>.bundle` (default); `flat` → `<backup_dir>/<repo>_<ts>.bundle`. |
| `-d, --depth N` | Directory depth to search for repositories (default: 2). |
| `-t, --tag TAG` | Name of the marker tag for the last backup (default: `lastBackup`). |
| `--dry-run` | Show which repositories and bundle files would be created, without changing anything. |
| `-h, --help` | Show help and exit. |

### Examples

Back up a single repository into `/backup` (nested layout):
```
backup-git.sh /path/to/repository /backup
```

Back up every repository found under `~/projects` into `/backup`:
```
backup-git.sh ~/projects /backup
```

Only back up repositories whose name starts with `web-`:
```
backup-git.sh --name 'web-*' ~/projects /backup
```

Back up several name patterns at once:
```
backup-git.sh --name 'web-*' --name 'api-*' ~/projects /backup
```

Back up a specific branch (or several branches):
```
backup-git.sh --branch develop ~/projects /backup
backup-git.sh --branch master --branch release ~/projects/app /backup
```

Use the old flat layout (all bundles in one directory):
```
backup-git.sh --layout flat ~/projects /backup
```

**Preview first** — list which repositories and bundles would be created,
without writing anything:
```
backup-git.sh --dry-run --name 'web-*' --branch develop ~/projects /backup
```
Example output:
```
INFO: DRY-RUN - no bundles will be created
INFO: scanning '~/projects' (depth 2) -> '/backup' [layout: nested, branches: develop]
PLAN: web-api [initial]     -> /backup/web-api/web-api_20260616-101501.bundle (branches: develop)
PLAN: web-ui  [incremental] -> /backup/web-ui/web-ui_20260616-101501.bundle (branches: develop)
----
INFO: dry-run summary: matched=2, would-backup=2, skipped(no-change)=0, errors=0
```

Restore
----------
```
backup-git-restore.sh [OPTIONS] <restore_dir> <repo_name>
```
Restores `<repo_name>` into `<restore_dir>/<repo_name>`. Bundles are looked up
under the source directory in **both** layouts and applied oldest-first (the
file-name timestamp defines the order): the first bundle is cloned, the
following ones are pulled.

```
nested:  <source>/<repo_name>/<repo_name>_*.bundle
flat:    <source>/<repo_name>_*.bundle
```

Options:

| Option | Description |
| ------ | ----------- |
| `-s, --source DIR` | Directory that holds the bundle files (default: current directory). |
| `--dry-run` | List the bundles that would be applied, in order, then exit. |
| `-h, --help` | Show help and exit. |

### Examples

Restore from the current directory (run the script from inside the backup dir):
```
cd /backup
backup-git-restore.sh /tmp/git repository
```

Restore without changing directory, pointing at the backup dir (layout is
auto-detected):
```
backup-git-restore.sh --source /backup /tmp/git repository
```

Preview the restore — list the bundles that would be applied, in order:
```
backup-git-restore.sh --source /backup --dry-run /tmp/git repository
```

Notes
----------
* Backups are **incremental**: keep using the *same* `<backup_dir>` and
  `--layout` for a given repository so the full bundle and all later increments
  stay together. A standalone incremental bundle cannot be restored without the
  earlier bundles in the same chain.
* With multiple `--branch` options the initial bundle is a full snapshot of the
  selected branches; the marker tag follows the first branch in the list.
* The backup exits non-zero if any repository failed (e.g. a missing branch),
  so it is safe to use in scripts and cron jobs.

Testing
----------
The test suite clones a repository from a bundle file, creates several
incremental backups and then restores it. It also exercises the new behaviour:
nested layout, `--dry-run`, `--name` filtering, branch validation and the
restore dry-run.

```
cd test
./run.sh
```
The suite prints `OK` and exits `0` on success.
