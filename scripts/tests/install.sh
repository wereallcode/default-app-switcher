#!/bin/bash
# Runs the installer in temporary home directories with download and build stubs.
set -euo pipefail

installer="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/das-installer-tests.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
checks=0
case=0

fail_check() {
  printf 'FAIL [%s]: %s\n' "$name" "$*" >&2
  [[ -z "${output:-}" ]] || printf '%s\n' "$output" >&2
  exit 1
}

# Creates a fresh environment: $dir, $home, $tools, $root, $bin, $archive, $log.
setup() {
  name="$1"
  case=$((case + 1))
  dir="$sandbox/$case"
  home="$dir/home with spaces"
  tools="$dir/tools"
  root="$home/.local/share/default-app-switcher"
  bin="$home/.local/bin/das"
  archive="$dir/release.tar.gz"
  log="$dir/build.log"
  mkdir -p "$home" "$tools" "$dir/source/scripts" "$dir/source/app/Sources/Core"
  printf '#!/bin/bash\nprintf "%%s\\n" "${TEST_PLATFORM:-Darwin}"\n' > "$tools/uname"
  printf '#!/bin/bash\nprintf "Apple Swift version %%s (test)\\n" "${TEST_SWIFT:-6.0}"\n' > "$tools/swift"
  printf '#!/bin/bash\nexit 0\n' > "$tools/codesign"
  cat > "$tools/curl" <<'STUB'
#!/bin/bash
for ((i = 1; i <= $#; i++)); do [[ "${!i}" == --output ]] && { j=$((i + 1)); output="${!j}"; }; done
url="${!#}"
if [[ "$url" == */releases/latest ]]; then
  [[ "${TEST_DOWNLOAD_FAILURE:-}" != release ]] || exit 22
  printf '{"tag_name":"%s","draft":false,"prerelease":%s,"body":null}' \
    "${TEST_TAG:-v1.2.3}" "${TEST_PRERELEASE:-false}" > "$output"
else
  [[ "${TEST_DOWNLOAD_FAILURE:-}" != archive ]] || exit 22
  cp "$TEST_ARCHIVE" "$output"
fi
STUB
  cat > "$dir/source/scripts/build.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'build %s\n' "$CONFIGURATION" >> "$TEST_BUILD_LOG"
[[ "${TEST_BUILD_FAILURE:-}" != 1 ]] || exit 1
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' "$root/app/Sources/Core/AppMetadata.swift")
mkdir -p "$root/dist/das-helper.app/Contents/MacOS"
printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "$version" > "$root/dist/das"
chmod +x "$root/dist/das"
STUB
  chmod +x "$tools"/*
  printf 'MIT\n' > "$dir/source/LICENSE"
  release 1.2.3
}

release() {
  printf 'package enum AppMetadata {\n    package static let version = "%s"\n}\n' "$1" \
    > "$dir/source/app/Sources/Core/AppMetadata.swift"
  tar -czf "$archive" -C "$dir" source
}

# Runs the installer from a file; set PIPED=1 to stream it through stdin like curl | bash.
run() {
  local status=0
  if [[ "${PIPED:-}" == 1 ]]; then
    output=$(env HOME="$home" SHELL="${TEST_SHELL:-/bin/zsh}" ZDOTDIR="${TEST_ZDOTDIR:-$home}" \
      PATH="${TEST_PATH:-$tools:/usr/bin:/bin}" TEST_ARCHIVE="$archive" TEST_BUILD_LOG="$log" \
      /bin/bash -s -- "$@" < "$installer" 2>&1) || status=$?
  else
    output=$(env HOME="$home" SHELL="${TEST_SHELL:-/bin/zsh}" ZDOTDIR="${TEST_ZDOTDIR:-$home}" \
      PATH="${TEST_PATH:-$tools:/usr/bin:/bin}" TEST_ARCHIVE="$archive" TEST_BUILD_LOG="$log" \
      /bin/bash "$installer" "$@" < /dev/null 2>&1) || status=$?
  fi
  return "$status"
}

succeeds() { run "$@" || fail_check "expected success: $*"; }
fails() { if run "$@"; then fail_check "expected failure: $*"; fi; }
expect() { "$@" || fail_check "assertion failed: $*"; checks=$((checks + 1)); }
contains() { [[ "$output" == *"$1"* ]]; }
link_is() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]]; }
no_leftovers() { ! compgen -G "$root/.staging.*" > /dev/null && [[ ! -e "$root/.install-lock" ]]; }
home_empty() { [[ -z "$(ls -A "$home")" ]]; }

setup "installs from piped input into a home directory containing spaces"
PIPED=1 succeeds
expect link_is "$bin" "$root/current/dist/das"
expect link_is "$root/current" "$root/v1.2.3"
expect [ "$("$bin" --version)" == 1.2.3 ]
expect [ -d "$root/v1.2.3/dist/das-helper.app" ]
expect [ -f "$root/v1.2.3/LICENSE" ]
expect grep -Fqx 'build release' "$log"
expect grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$home/.zshrc"
expect no_leftovers

setup "reuses an installed version and adds PATH only once"
printf '# Existing shell configuration\n' > "$home/.zshrc"
succeeds
succeeds
expect [ "$(wc -l < "$log")" -eq 1 ]
expect [ "$(head -n 1 "$home/.zshrc")" == '# Existing shell configuration' ]
expect [ "$(grep -c 'export PATH=' "$home/.zshrc")" -eq 1 ]

setup "keeps the working version when an archive has the wrong version"
succeeds
TEST_TAG=v2.0.0 fails
expect contains 'does not match its version tag'
expect link_is "$root/current" "$root/v1.2.3"
expect no_leftovers

setup "leaves no active installation when the build fails"
TEST_BUILD_FAILURE=1 fails
expect [ ! -e "$bin" ]
expect [ ! -e "$home/.zshrc" ]
expect no_leftovers

setup "switches to a newer release only after a successful build"
succeeds
release 2.0.0
TEST_TAG=v2.0.0 TEST_BUILD_FAILURE=1 fails
expect link_is "$root/current" "$root/v1.2.3"
TEST_TAG=v2.0.0 succeeds
expect link_is "$root/current" "$root/v2.0.0"
expect [ "$("$bin" --version)" == 2.0.0 ]
expect [ -x "$root/v1.2.3/dist/das" ]

setup "does not replace an unmanaged installation directory"
mkdir -p "$root"
printf 'keep' > "$root/user-file"
fails
expect contains 'unmanaged directory'
expect [ "$(cat "$root/user-file")" == keep ]

setup "does not change the home directory when no release is available"
TEST_DOWNLOAD_FAILURE=release fails
expect contains 'published GitHub Release'
expect home_empty

setup "preserves the active version and profile when the archive download fails"
succeeds
cp "$home/.zshrc" "$dir/zshrc.before"
TEST_TAG=v2.0.0 TEST_DOWNLOAD_FAILURE=archive fails
expect link_is "$root/current" "$root/v1.2.3"
expect cmp -s "$home/.zshrc" "$dir/zshrc.before"
expect no_leftovers

setup "cleans up after an invalid archive"
printf 'not an archive' > "$archive"
fails
expect [ ! -e "$bin" ]
expect no_leftovers

setup "rejects invalid and prerelease tags without creating an installation"
for tag in ../../elsewhere v1.0.0-beta.1 master v01.0.0 1.0.0; do
  TEST_TAG="$tag" fails
  expect home_empty
done
TEST_PRERELEASE=true fails
expect home_empty

setup "refuses an unrelated command"
mkdir -p "$home/.local/bin"
printf 'user command' > "$bin"
fails
expect [ "$(cat "$bin")" == 'user command' ]

setup "refuses unsupported platforms and old Swift"
TEST_PLATFORM=Linux fails
expect contains 'macOS only'
TEST_SWIFT=5.10 fails
expect contains 'Swift 6 or later'
expect home_empty

setup "does not remove another installer's lock"
mkdir -p "$root/.install-lock"
touch "$root/.installer-managed"
fails
expect contains 'Another installation may be running'
expect [ -d "$root/.install-lock" ]
expect [ ! -e "$log" ]

setup "uses the active bash login profile"
for profile in .bash_login .profile; do
  rm -f "$home/.bash_login" "$home/.profile"
  printf 'export DAS_PROFILE_MARKER=preserved\n' > "$home/$profile"
  TEST_SHELL=/bin/bash succeeds
  expect [ ! -e "$home/.bash_profile" ]
  expect [ ! -e "$home/.zshrc" ]
  shell=$(env -i HOME="$home" PATH=/usr/bin:/bin /bin/bash --login -c \
    'printf "%s\n" "$DAS_PROFILE_MARKER"; command -v das')
  expect [ "$shell" == "preserved"$'\n'"$bin" ]
done
rm -f "$home/.bash_login" "$home/.profile"
TEST_SHELL=/bin/bash succeeds
expect grep -Fq 'export PATH=' "$home/.bash_profile"

setup "uses a custom zsh configuration directory"
mkdir "$home/zsh settings"
TEST_ZDOTDIR="$home/zsh settings" succeeds
expect [ ! -e "$home/.zshrc" ]
shell=$(env -i HOME="$home" ZDOTDIR="$home/zsh settings" PATH=/usr/bin:/bin /bin/zsh -d -i -c 'command -v das' 2>/dev/null)
expect [ "$shell" == "$bin" ]

setup "leaves shell settings alone when the install directory is on PATH or the shell is unknown"
TEST_PATH="$home/.local/bin:$tools:/usr/bin:/bin" succeeds
expect [ ! -e "$home/.zshrc" ]
TEST_SHELL=/bin/fish succeeds
expect contains 'Add ~/.local/bin to your shell configuration'
expect [ ! -e "$home/.zshrc" ]

setup "uninstalls through a pipe, preserves unrelated files and can run again"
succeeds
release 2.0.0
TEST_TAG=v2.0.0 succeeds
cp "$home/.zshrc" "$dir/zshrc.before"
printf 'keep' > "$home/.local/bin/another-tool"
PIPED=1 succeeds --uninstall
expect [ ! -e "$root" ]
expect [ ! -L "$bin" ]
expect [ "$(cat "$home/.local/bin/another-tool")" == keep ]
expect cmp -s "$home/.zshrc" "$dir/zshrc.before"
succeeds --uninstall
TEST_TAG=v2.0.0 succeeds

setup "uninstall does not build and does not follow nested links"
mkdir -p "$root"
touch "$root/.installer-managed"
printf 'untouched' > "$home/keep"
ln -s "$home/keep" "$root/current"
TEST_PATH="$dir/empty:/usr/bin:/bin" TEST_DOWNLOAD_FAILURE=release succeeds --uninstall
expect [ ! -e "$root" ]
expect [ "$(cat "$home/keep")" == untouched ]
expect [ ! -e "$log" ]

for kind in unmarked "root symlink" "marker symlink"; do
  setup "refuses an unsafe uninstall: $kind"
  mkdir -p "$home/outside" "$home/.local/share" "$home/.local/bin"
  printf 'keep' > "$home/outside/.installer-managed"
  if [[ "$kind" == "root symlink" ]]; then
    ln -s "$home/outside" "$root"
  else
    mkdir "$root"
    [[ "$kind" != "marker symlink" ]] || ln -s "$home/outside/.installer-managed" "$root/.installer-managed"
  fi
  ln -s "$root/current/dist/das" "$bin"
  fails --uninstall
  expect contains 'unmanaged directory'
  expect [ -e "$root" ]
  expect [ -L "$bin" ]
  expect [ "$(cat "$home/outside/.installer-managed")" == keep ]
done

setup "uninstall preserves an existing lock"
mkdir -p "$root/.install-lock"
touch "$root/.installer-managed"
fails --uninstall
expect contains 'Another installation'
expect [ -d "$root/.install-lock" ]
expect [ -f "$root/.installer-managed" ]

for link in false true; do
  setup "uninstall preserves an unrelated command (symlink: $link)"
  mkdir -p "$root" "$home/.local/bin"
  touch "$root/.installer-managed"
  printf 'keep' > "$home/other-cli"
  if [[ "$link" == true ]]; then ln -s "$home/other-cli" "$bin"; else printf 'keep' > "$bin"; fi
  succeeds --uninstall
  expect contains 'Preserved unrelated command'
  expect [ "$(cat "$bin")" == keep ]
  expect [ ! -e "$root" ]
done

setup "uninstall removes an owned dangling command link"
mkdir -p "$home/.local/bin"
ln -s "$root/current/dist/das" "$bin"
succeeds --uninstall
expect [ ! -L "$bin" ]
expect [ ! -e "$root" ]

setup "shows help and rejects unexpected arguments without installing"
PIPED=1 succeeds --help
expect contains '--uninstall'
fails --uninstal
fails --uninstall extra
expect home_empty
expect [ ! -e "$log" ]

printf 'Passed %s installer checks.\n' "$checks"
