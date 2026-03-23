# Claude for Arch

Install and update Claude Desktop on Arch Linux using system Electron and a lightweight script-based workflow.

## Status

This project is community-maintained and is not affiliated with Anthropic.

## Legal Notice

**Important:** This project is not an official installation method for Claude Desktop. The scripts automate installation and updates, but:

- **No repackaging**: The Claude Desktop binary is downloaded directly from Anthropic's official servers—this project does not redistribute, modify, or repackage the binary.
- **Users agree to Claude's Terms**: Anyone using these scripts must comply with Claude Desktop's End User License Agreement and Terms of Service.
- **Not endorsed by Anthropic**: Anthropic has not endorsed this project. They may request removal at any time.
- **Use at your own risk**: This is an unofficial community project created for educational purposes.

For official installation guidance, see the [Claude Desktop documentation](https://docs.anthropic.com/en/docs/build-a-bot/desktop-app).

## Support matrix

- Distribution: Arch Linux (primary target)
- Shell: bash
- Desktop: X11-focused launcher behavior (uses `xdpyinfo` and `wmctrl`)
- CI coverage: script linting, formatting checks, and updater help smoke check

Known limitation:

- The scripts attempt to auto-detect the Electron resources directory. If detection fails on custom setups, set `ELECTRON_RESOURCES_DIR` manually.

## What this repo includes

- `claude-install-simple.sh`: initial install script
- `claude-auto-update.sh`: update checker and installer

## Features

- ✅ **Global hotkey**: Ctrl+Alt+Space to launch Claude Desktop (registered via desktop entry)
- ✅ **MCP Server support**: Claude Desktop can load and use Model Context Protocol servers
- ✅ **Desktop integration**: Claude appears in application menus and can handle URI schemes
- ✅ **Auto-detection**: Automatically detects Electron installation path on your system
- ✅ **Easy updates**: Simple command to check for and install new Claude versions
- ✅ **Backup & rollback**: Automatic backups before updates with easy rollback capability
- ✅ **Clean installation**: Uses symlinks instead of copying files to minimize disk usage

## Requirements

- Arch Linux (or compatible)
- `sudo` access for writing Electron resource symlinks
- Packages used by the scripts:
	- `electron`
	- `curl`
	- `p7zip`
	- `nodejs`
	- `asar`
	- `xorg-xdpyinfo`
	- `wmctrl`

Install dependencies:

```bash
sudo pacman -S electron curl p7zip nodejs asar xorg-xdpyinfo wmctrl
```

## Quick start

Clone and run:

```bash
git clone https://github.com/heet06/Claude-for-Arch.git
cd Claude-for-Arch
chmod +x claude-install-simple.sh claude-auto-update.sh
./claude-install-simple.sh
```

If auto-detection fails for your Electron layout:

```bash
ELECTRON_RESOURCES_DIR=/usr/lib/electron39/resources ./claude-install-simple.sh
```

## Update workflow

Check only:

```bash
./claude-auto-update.sh --check
```

Interactive update:

```bash
./claude-auto-update.sh
```

Automatic update:

```bash
./claude-auto-update.sh --auto
```

## Troubleshooting

Check updater options:

```bash
./claude-auto-update.sh --help
```

Check if an update is available:

```bash
./claude-auto-update.sh --check
echo $?
```

Exit code behavior for `--check`:

- `0`: already up to date
- `1`: update available or check failed

Common fixes:

- Reinstall missing dependencies listed in the Requirements section.
- Confirm the electron resource directory exists and matches your installed package.
- Provide a manual override when needed:

```bash
ELECTRON_RESOURCES_DIR=/path/to/electron/resources ./claude-auto-update.sh
```
- Re-run install script after Arch/Electron upgrades.

## Uninstall

Remove installation directory:

```bash
rm -rf "$HOME/claude-desktop-build"
```

Remove desktop entry and icon:

```bash
rm -f "$HOME/.local/share/applications/claude-desktop.desktop"
rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/claude.png"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
```

Optional: remove Claude user config:

```bash
rm -rf "$HOME/.config/Claude"
```

## Safety notes

- The scripts create symlinks inside your detected Electron resources directory.
- Keep local backups before major system upgrades.
- Review scripts before running in production environments.

## Contributing

Please read CONTRIBUTING.md before opening pull requests.

## Security

Please report vulnerabilities privately as described in SECURITY.md.

## License

This project is licensed under the MIT License. See LICENSE for details.
