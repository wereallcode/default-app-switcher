# Troubleshooting

Check the command path and version.

```bash
command -v das && das --version
```

- If `das` is not found, check the `PATH` line in your shell startup file.
- Keep `dist/das` and `dist/das-helper.app` together.
- If you move the clone or run `make clean`, `das` becomes unavailable.
