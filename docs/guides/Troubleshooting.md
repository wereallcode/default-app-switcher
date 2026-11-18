# Troubleshooting

This guide covers solutions to the following common problems.

## 1. `das` is not found

Check the command path.

```bash
command -v das
```

If nothing is printed, check the `PATH` line in your shell startup file.

- Installer: `$HOME/.local/bin`
- [Manual Installation](Manual-Installation.md): `$HOME/.default-app-switcher/dist`

## 2. The helper application was not found

`das` needs `das-helper.app` next to it.

- Installer: uninstall, then run the installation command again.
- Manual Installation: run `make build` in the clone.
