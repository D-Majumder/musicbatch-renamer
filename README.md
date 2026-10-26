# MusicBatch Renamer

MusicBatch Renamer is a free, open-source Windows utility that organises music libraries through safe alphabetical renaming. It includes a graphical interface, live preview, collision detection, configurable numbering, and CSV-based undo support. Built with PowerShell and Windows Forms, it runs locally without third-party dependencies and never intentionally modifies audio contents.



Built for music lovers who want a clean, consistently numbered offline music collection.

A free, local-only Windows utility for alphabetically renumbering music files. Includes a graphical interface, preview, collision checks, CSV undo manifests, and a command-line preview mode.

**It renames files only. It does not open, encode, convert, or modify audio contents.**

## Features

* GUI built with Windows PowerShell and Windows Forms; no third-party modules required.
* Alphabetical ordering by cleaned song title, with filename as a deterministic tie-breaker.
* Recognizes and removes common numeric prefixes such as `1. `, `02 - `, `003) ` and `4\_ `.
* Supports MP3, WAV, M4A, AAC, FLAC, OGG, WMA, AIFF, AIF, and OPUS extensions.
* Configurable filename format, default `{0:D3}. {1}{2}` (`001. Song Title.mp3`).
* Preview before renaming; explicit confirmation required.
* Detects duplicate generated names and occupied destinations before renaming.
* Uses a two-phase temporary rename to avoid normal filename collisions.
* Writes an undo CSV manifest before changes and provides a GUI undo action.
* Runs locally; no network, telemetry, accounts, or administrator privileges required for ordinary folders.

## Requirements

* Windows 10 or Windows 11
* Windows PowerShell 5.1 (included with Windows)
* No installation or third-party dependencies

> This project uses Windows Forms and is intended for Windows PowerShell on Windows, not PowerShell on macOS/Linux.

## Quick start

1. Extract the ZIP to a normal folder, for example `D:\\MusicBatch-Renamer`.
2. Double-click `Start-MusicBatchRenamer.bat`.
3. Choose the folder containing your songs and click **Preview**.
4. Check the old and new names.
5. Click **Rename files** and confirm.

If Windows warns about running scripts, inspect the source first. The launcher uses `-ExecutionPolicy Bypass` only for this process; it does not change your machine-wide execution policy.

### Example

Before:

```text
10. Alfaaz.mp3
2. Chitta.mp3
3. Noori.mp3
1. Tu Jaane Na.mp3
```

After alphabetical sorting:

```text
001. Alfaaz.mp3
002. Chitta.mp3
003. Noori.mp3
004. Tu Jaane Na.mp3
```

The actual order is determined by the cleaned song title, not the old number.

## Command-line mode

Open PowerShell in the extracted project directory.

Preview only:

```powershell
.\\MusicBatchRenamer.ps1 -Folder "C:\\Users\\YourName\\Music" -Preview
```

Interactive command-line rename:

```powershell
.\\MusicBatchRenamer.ps1 -Folder "C:\\Users\\YourName\\Music" -NoGui
```

The CLI asks you to type `RENAME` after showing the proposed changes.

## Undo

After a successful rename, a file named similar to `MusicBatchRenamer-undo-20261026-143000.csv` is saved in the music folder. In the GUI, click **Undo from CSV...** and select that manifest. Undo is blocked if an original path is already occupied or a renamed file is missing.

Keep the manifest until you are satisfied with the result. A separate backup is still recommended before bulk file operations.

## Sorting and filename format

Default format:

```text
{0:D3}. {1}{2}
```

* `{0:D3}` = three-digit number (`001`, `002`, ...)
* `{1}` = cleaned title
* `{2}` = original extension

Examples:

* `{0:D2} - {1}{2}` → `01 - Song.mp3`
* `{0:D3}\_{1}{2}` → `001\_Song.mp3`

The tool does not edit embedded ID3 tags or other metadata. It does not currently group songs by album or infer artist/title from tags. It operates on one selected folder at a time; subfolder recursion is intentionally not enabled in this release.

## Safety notes

* Preview does not modify anything.
* Destination collisions are rejected before the rename begins.
* The tool creates an undo manifest before renaming.
* If an operation fails mid-run, it attempts rollback, but no file-operation tool can guarantee recovery from every disk, permission, or process failure. Keep a backup for important collections.
* If two files have the same cleaned title and extension, the tool stops rather than overwrite or silently disambiguate them.
* Files are never deleted by the normal workflow.

## Repository layout

```text
MusicBatch-Renamer/
├── MusicBatchRenamer.ps1
├── Start-MusicBatchRenamer.bat
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── .gitignore
├── docs/
│   └── SAFETY.md
├── tests/
│   └── Manual-Test-Plan.md
└── .github/
    └── workflows/
        └── powershell-parse.yml
```

## License

MIT. See `LICENSE`.

