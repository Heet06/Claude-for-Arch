# Contributing to Claude for Arch

Thank you for contributing.

## Before opening a PR

- Open an issue first for larger changes.
- Keep behavior changes explicit and documented.
- Test the scripts on a clean Arch environment when possible.

## Local checks

Run these before opening a PR:

```bash
shellcheck -x claude-install-simple.sh claude-auto-update.sh
shfmt -d -i 4 -ci claude-install-simple.sh claude-auto-update.sh
./claude-auto-update.sh --help
```

If `shfmt` rewrites output is desired, use:

```bash
shfmt -w -i 4 -ci claude-install-simple.sh claude-auto-update.sh
```

## Development guidelines

- Keep scripts POSIX-friendly where practical.
- Prefer clear logging and safe failure behavior.
- Avoid destructive operations unless clearly documented and confirmed.
- Keep dependencies minimal.

## Pull request checklist

- I tested install and/or update paths relevant to my change.
- I updated README.md or inline script help where behavior changed.
- I kept changes focused and avoided unrelated refactors.
- I confirmed shell scripts are executable and lint-clean when possible.
- I ran the local checks in this document.
- I considered failure and rollback behavior for update path changes.

## Testing guidance

- For install changes, verify from a clean state in `$HOME/claude-desktop-build`.
- For update changes, validate both `--check` and normal update flow.
- Include key terminal output in PR description when behavior changes.

## Commit style

Small, focused commits are preferred. Suggested format:

- feat: add feature
- fix: correct behavior
- docs: update documentation
- chore: maintenance only

## Code of Conduct

By participating, you agree to follow CODE_OF_CONDUCT.md.
