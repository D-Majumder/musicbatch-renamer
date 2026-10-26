# Manual Test Plan

Run these tests only in a disposable test directory, never on the only copy of a music collection.

## Setup

Create copies of a few harmless test files and rename the copies to:

- `10. Alfaaz.mp3`
- `2. Chitta.mp3`
- `3. Noori.mp3`
- `1. Tu Jaane Na.mp3`
- `cover.jpg` (should be ignored)
- `notes.txt` (should be ignored)

## Cases

1. Open the GUI and select the test directory.
2. Click Preview. Confirm the list is alphabetically ordered and no files have changed.
3. Cancel at the confirmation prompt. Confirm no filenames changed.
4. Run rename. Confirm expected numbered filenames and a CSV undo map appear.
5. Use Undo from CSV. Confirm original filenames are restored.
6. Create two files whose cleaned titles collide, such as `1. Song.mp3` and `2. Song.mp3`. Confirm preview stops with a collision message and changes nothing.
7. Set a format such as `{0:D2} - {1}{2}` and confirm output is `01 - Alfaaz.mp3`.
8. Confirm non-audio files are ignored.
9. Test a folder with zero supported audio files.
10. Test a folder with Unicode titles and spaces.
11. Test a file locked by another process where feasible; verify an error is shown and inspect rollback results.
12. Compare file sizes or hashes before and after to verify only filenames changed.
