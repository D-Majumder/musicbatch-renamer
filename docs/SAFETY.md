# Safety model and limitations

## What changes

The application changes filenames within the selected folder. It does not decode or modify the bytes of an audio file.

## Protections

- Preview is read-only.
- A confirmation is required before renaming.
- Generated destination names are checked for duplicates.
- Existing destinations outside the rename set cause the operation to stop.
- A CSV map is written before any rename.
- Files are first moved to unique temporary names, then to final names to avoid common cycles and collisions.
- Undo checks that all renamed files exist and original paths are free before starting.

## Limits

No multi-file rename can be made perfectly atomic across every filesystem and failure mode. Power loss, a process termination, antivirus locks, permissions changes, or disk errors can interrupt a transaction. The program attempts rollback on a caught error, but users should back up valuable files first.

The tool sorts by filename title, not audio tags. It intentionally stops on duplicate generated names instead of adding arbitrary suffixes. The current release only processes the selected folder's immediate files; nested folder support is not enabled.
