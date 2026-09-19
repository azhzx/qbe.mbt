#!/usr/bin/env sh
# Bootstrap qbe.mbt on macOS or Linux.

set -eu

skip_install=0
install_moon=0
assume_yes=0

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap.sh [--skip-install] [--install-moon] [--yes]

  --skip-install   Do not attempt to install MoonBit CLI.
  --install-moon   Attempt to install MoonBit CLI when it is missing.
  --yes            Do not prompt before an installation attempt.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-install) skip_install=1 ;;
    --install-moon) install_moon=1 ;;
    --yes|-y) assume_yes=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

die() {
  echo "error: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git is required; install git and retry"
command -v make >/dev/null 2>&1 || die "make is required to build vendor/qbe"

if [ ! -f .gitmodules ] || ! grep -q 'path = vendor/qbe' .gitmodules; then
  die "the vendor/qbe submodule is not declared in .gitmodules"
fi

echo "[bootstrap] Initializing vendor/qbe..."
git submodule update --init --recursive vendor/qbe ||
  die "could not initialize vendor/qbe"
[ -f vendor/qbe/Makefile ] || die "vendor/qbe/Makefile is missing"

echo "[bootstrap] Building vendor/qbe..."
(cd vendor/qbe && make) || die "vendor/qbe build failed"

if command -v moon >/dev/null 2>&1; then
  moon_cmd=$(command -v moon)
else
  moon_cmd=
fi

if [ -z "$moon_cmd" ] && [ "$skip_install" -eq 0 ] && [ "$install_moon" -eq 1 ]; then
  if [ "$assume_yes" -eq 0 ]; then
    printf "MoonBit CLI is missing. Attempt installation? [y/N] "
    read answer || answer=n
  else
    answer=y
  fi

  if [ "$answer" = y ] || [ "$answer" = Y ]; then
    case "$(uname -s)" in
      Darwin)
        command -v brew >/dev/null 2>&1 ||
          die "Homebrew is required for automatic macOS installation; install MoonBit manually"
        brew install moonbit ||
          die "MoonBit installation failed"
        ;;
      Linux)
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL https://moonbitlang.com/install.sh | sh ||
            die "MoonBit installation failed"
        elif command -v wget >/dev/null 2>&1; then
          wget -qO- https://moonbitlang.com/install.sh | sh ||
            die "MoonBit installation failed"
        else
          die "curl or wget is required for automatic MoonBit installation"
        fi
        ;;
      *)
        die "unsupported operating system; install MoonBit CLI manually"
        ;;
    esac
  else
    echo "[bootstrap] MoonBit installation skipped."
  fi
fi

if [ -z "$moon_cmd" ] && command -v moon >/dev/null 2>&1; then
  moon_cmd=$(command -v moon)
fi

[ -n "$moon_cmd" ] ||
  die "MoonBit CLI is required for smoke checks; install it or rerun with --install-moon"

echo "[bootstrap] Running moon info..."
"$moon_cmd" info || die "moon info failed"
echo "[bootstrap] Running moon build..."
"$moon_cmd" build || die "moon build failed"
echo "[bootstrap] Running moon test..."
"$moon_cmd" test || die "moon test failed"
echo "[bootstrap] Bootstrap completed successfully."
