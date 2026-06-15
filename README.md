git-backup
==========
Simple shell scripts for creating and restoring incremental backups of git repositories using git bundles.

The backup routine uses `git bundle create --all lastBackup..master` to create incremental bundles.
After restoring, only the `master` branch will be present.

Project layout
--------------
```
src/
  lib.sh                  shared helpers (logging, directory navigation, bundle ops)
  backup-git.sh           create incremental bundle backups
  backup-git-restore.sh   restore a repository from bundle files
test/
  lib_test.sh             shared test helpers (phase labels, assertions)
  run.sh                  end-to-end test orchestrator
  test-fill-repo.sh       add a commit + run one backup round
  test-restore-repo.sh    restore from bundles and report result
  repo.bundle             seed bundle used by the test suite
```

Backup
------
Create a backup of a single repository and save it into `/backup`:
```
backup-git.sh /path/to/repository /backup
```

Create backups of multiple repositories located in `~/projects` and save them into `/backup`:
```
backup-git.sh ~/projects /backup
```

Restore
-------
Restore a repository named `repository` into `/tmp/git/repository` by running
the restore script from the directory that contains the `repository_*.bundle` files:
```
backup-git-restore.sh /tmp/git repository
```

Testing
-------
The test suite clones a repository from a seed bundle, simulates 10 incremental
commits (running the backup after each one), and then restores the repository
from the resulting bundles.

```
cd test
./run.sh
```

The output is split into labelled phases (`[BACKUP]`, `[RESTORE]`, `[TEST]`),
so a failure immediately shows whether the backup or restore pipeline broke.
