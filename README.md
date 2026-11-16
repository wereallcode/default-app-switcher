# Default App Switcher

Switch macOS default applications from the terminal.

## Why?

Choose your default `browser` and apps for web links, email links and file types in one terminal interface.

## Preview

<img src="docs/assets/preview.png" alt="Default App Switcher" width="500" />

## Installation

### Requirements

- `macOS` with `Xcode Command Line Tools` and `Swift 6` or later — install them with `xcode-select --install`.

### Quick Start

Run this command in your terminal to download and build the latest published release.

```bash
curl -fsSL https://raw.githubusercontent.com/wereallcode/default-app-switcher/master/scripts/install.sh | bash
```

Open a new terminal and run `das`; use `das --help` or `das --version` for details.

_If `das` is not found, follow the installer's instructions to add `$HOME/.local/bin` to your shell's `PATH`._

#### Update

Run the installation command again to update to the latest release.

#### Uninstall

To uninstall the release installation, run:

```bash
curl -fsSL https://raw.githubusercontent.com/wereallcode/default-app-switcher/master/scripts/install.sh | bash -s -- --uninstall
```

This removes Default App Switcher's installed files and command link; your default app settings and shell configuration are preserved.

## Guides

- [Manual Installation](docs/guides/Manual-Installation.md)
- [Troubleshooting](docs/guides/Troubleshooting.md)
