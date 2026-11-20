# safe-file-deleter

Moves files into a trash directory with metadata so they can be restored later,
instead of unlinking them permanently.

## Usage

```bash
source ./safe_file_deleter.sh

# Move a file into the trash. Prints the entry name.
entry=$(sfd_trash ./report.txt /tmp/my-trash)

# List what is currently restorable.
sfd_list /tmp/my-trash

# Put it back where it came from. Prints the restored path.
sfd_restore "$entry" /tmp/my-trash
```

The trash root defaults to `$SFD_TRASH_ROOT`, or
`$HOME/.local/share/safe-file-deleter` if that variable is unset. Every function
also takes an explicit root as its last argument, which is what the tests use.

Exported functions:

- `sfd_trash <path> [trash_root]` — move a regular file into the trash, print the entry name.
- `sfd_restore <entry> [trash_root]` — move a payload back to its recorded original path, print that path.
- `sfd_list [trash_root]` — print each restorable entry name, one per line.
- `sfd_read_meta <meta_file> <key>` — read a single key from an entry metadata file.

## Why this exists

`rm` is fast and final. A trash directory is easy to build badly: if you only
move the file and forget where it came from, restore is impossible; if you store
the original path by sourcing the metadata file, a payload whose name contains
shell syntax can execute code when you restore it. This library stores the
original absolute path as a plain `key=value` line and parses it with a read
loop, so restoring never evaluates anything from the payload.

The trade-off is that the trash root is a flat directory of entry folders, each
holding a `payload` and a `meta` file. That is simple and inspectable, but it
means two files with the same basename trashed in the same second need a numeric
suffix to stay distinct, which the entry naming handles. It also means the
metadata is not a database: there is no index, so `sfd_list` walks the
directory. For a personal trash directory that is fine; for millions of entries
you would want a real store.

## Edge cases worth knowing

- `sfd_trash` refuses directories and missing paths. Trashing a directory would
  require recursive bookkeeping that this library deliberately does not do.
- `sfd_restore` refuses to overwrite an existing file at the original path. That
  protects newer data, but it means you must move or remove the conflicting file
  before restoring.
- Entry names are `<basename>.<epoch-seconds>` with a numeric suffix on
  collision. They are not stable across clocks; treat them as opaque handles
  returned by `sfd_trash`.
- `sfd_restore` recreates missing parent directories, so restoring into a tree
  that was cleaned up still works.
