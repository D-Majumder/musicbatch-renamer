# Contributing

Thanks for considering a contribution.

## Guidelines

- Keep the tool local-only; do not add telemetry or network calls without a clear, documented reason.
- Never read or rewrite audio payloads to perform filename operations.
- Add a manual test case for any new rename or undo behaviour.
- Preserve preview-first behaviour and reject collisions by default.
- Document supported PowerShell and Windows versions.
- Do not commit personal music files, undo manifests, or private paths.

## Suggested workflow

1. Create a feature branch.
2. Make the smallest focused change.
3. Run the parse check in `.github/workflows/powershell-parse.yml`.
4. Follow `tests/Manual-Test-Plan.md` on a disposable test folder.
5. Update README and CHANGELOG when user-visible behaviour changes.
