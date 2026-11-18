# Contributing

This guide covers the development setup, local checks and CI.

## 1. Setup

Run this once after cloning to enable the pre-push hook.

```bash
make hooks
```

## 2. Checks

Every push runs `make check` first: formatting, Swift tests, installer tests and the build.

Run it manually with `make check`.

## 3. CI

Hosted macOS runners often queued for hours, so CI runs only the Linux checks and the release.

The macOS checks run locally through the hook instead.
