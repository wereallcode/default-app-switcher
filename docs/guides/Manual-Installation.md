# Manual Installation

This guide covers manual installation, updates and removal.

## 1. Requirements

- A macOS version supported by your installed `Swift 6` toolchain to build from source.
- `Xcode Command Line Tools` with `Swift 6` or later.
- `Git` and `make` for building from source.

Install missing command line tools with `xcode-select --install`.

### 1.1. Compatibility

- The build targets `macOS 12` without automated compatibility testing for that version.
- The build and automated checks passed with `Swift 6.3.3` on `macOS 26.6.2` (`Apple Silicon`).

## 2. Install

Open a new terminal and follow these steps.

```bash
git clone https://github.com/wereallcode/default-app-switcher.git "$HOME/.default-app-switcher"
```

```bash
cd "$HOME/.default-app-switcher" && make build
```

Run `das` with this command.

```bash
./dist/das
```

`das` needs `das-helper.app` in the same directory; run `make build` again if it is missing.

### 2.1. Add to `PATH`

Follow these steps to add `das` to your `PATH` and run it from any directory.

```zsh
vi ~/.zshrc
```

Add this line at the end of the file and save it.

```zsh
export PATH="$HOME/.default-app-switcher/dist:$PATH"
```

Apply the change.

```zsh
source ~/.zshrc
```

Run `das`. 🥳

```zsh
das
```

If the shell still cannot find `das`, check that the line is saved and open a new terminal.

## 3. Update

Follow these steps to update your local copy and rebuild.

```bash
cd "$HOME/.default-app-switcher" && git pull --ff-only
```

```bash
make build
```

## 4. Uninstall

1. Remove the `PATH` line from your shell startup file.
2. Open a new terminal.
3. Delete `$HOME/.default-app-switcher` if you no longer need the source.
