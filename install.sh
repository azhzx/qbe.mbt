#!/usr/bin/env sh
# qbe.mbt installer: download a prebuilt native qbe and put it on PATH.
#
#   curl -fsSL https://i2pl.com/install-qbe-mbt.sh | sh
#   curl -fsSL https://i2pl.com/install-qbe-mbt.sh | sh -s -- --version v0.24.0
#
# It never builds from source. Assets come from the project's GitHub releases:
#   qbe-macos-aarch64  qbe-linux-x86_64  qbe-linux-aarch64
#
# Options:
#   --version TAG    Install a specific release tag (default: the latest).
#   --bin-dir DIR    Install directory (default: ~/.local/bin).
#   --base-url URL   Release base URL (default: the GitHub repo below).
#   --no-path        Do not edit the shell rc files.
#   --yes, -y        Never prompt.
#   --dry-run        Print what would happen and exit.
#   --help, -h       Show this help.
#
# Environment: QBE_MBT_VERSION, QBE_MBT_BIN_DIR, QBE_MBT_BASE_URL, NO_COLOR.

set -eu

REPO="${QBE_MBT_REPO:-azhzx/qbe.mbt}"
base_url="${QBE_MBT_BASE_URL:-https://github.com/${REPO}/releases}"
bin_dir="${QBE_MBT_BIN_DIR:-${HOME:-}/.local/bin}"
version="${QBE_MBT_VERSION:-}"
add_path=1
assume_yes=0
dry_run=0

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  BOLD="$(printf '\033[1m')" DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')" GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')" CYAN="$(printf '\033[36m')" RESET="$(printf '\033[0m')"
else
  BOLD= DIM= RED= GREEN= YELLOW= CYAN= RESET=
fi
step() { printf '\n%s\n' "${BOLD}${CYAN}[${1}] ${2}${RESET}" >&2; }
ok()   { printf '%s\n' "${GREEN}ok${RESET}  ${*}" >&2; }
info() { printf '%s\n' "${DIM}    ${*}${RESET}" >&2; }
warn() { printf '%s\n' "${YELLOW}!!${RESET}  ${*}" >&2; }
die()  { printf '%s\n' "${RED}xx${RESET}  ${*}" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install-qbe-mbt.sh [options]

  --version TAG    Install a specific release tag (default: the latest).
  --bin-dir DIR    Install directory (default: ~/.local/bin).
  --base-url URL   Release base URL (default: the GitHub repo).
  --no-path        Do not edit the shell rc files.
  --yes, -y        Never prompt.
  --dry-run        Print what would happen and exit.
  --help, -h       Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:?--version needs a tag}"; shift 2 ;;
    --bin-dir) bin_dir="${2:?--bin-dir needs a directory}"; shift 2 ;;
    --base-url) base_url="${2:?--base-url needs a URL}"; shift 2 ;;
    --no-path) add_path=0; shift ;;
    --yes | -y) assume_yes=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ -n "$bin_dir" ] || die "HOME is not set; pass --bin-dir"

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)
case "$uname_s" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) die "no prebuilt binary for '$uname_s' (macOS and Linux only)" ;;
esac
case "$uname_m" in
  arm64 | aarch64) arch=aarch64 ;;
  x86_64 | amd64) arch=x86_64 ;;
  *) die "no prebuilt binary for architecture '$uname_m'" ;;
esac
if [ "$os" = macos ] && [ "$arch" = x86_64 ]; then
  die "no prebuilt binary for Intel macOS: the MoonBit toolchain only targets Apple Silicon"
fi
asset="qbe-$os-$arch"

if [ -n "$version" ]; then
  asset_url="$base_url/download/$version/$asset"
  sums_url="$base_url/download/$version/SHA256SUMS"
else
  asset_url="$base_url/latest/download/$asset"
  sums_url="$base_url/latest/download/SHA256SUMS"
fi

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=15 -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

tty_read() { read -r _ans < /dev/tty 2>/dev/null || _ans=; }
have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

step 1/3 "Downloading $asset"
info "$asset_url"
if [ "$dry_run" -eq 1 ]; then
  info "dry run: would install to $bin_dir/qbe"
  exit 0
fi

tmp=$(mktemp 2>/dev/null) || die "cannot create a temporary file"
sums=$(mktemp 2>/dev/null) || sums=/dev/null
trap 'rm -f "$tmp" "$sums" 2>/dev/null || true' EXIT INT TERM

fetch "$asset_url" "$tmp" || die "download failed: $asset_url"
if fetch "$sums_url" "$sums" 2>/dev/null; then
  want=$(awk -v n="$asset" '$2 == n || $2 == "*"n { print $1 }' "$sums" | head -n 1)
  if [ -n "$want" ]; then
    got=$(sha256_of "$tmp") || got=
    [ -n "$got" ] || die "no sha256 tool available to verify $asset"
    [ "$got" = "$want" ] || die "checksum mismatch for $asset"
    ok "checksum verified"
  else
    warn "SHA256SUMS has no entry for $asset; skipping verification"
  fi
else
  warn "could not fetch SHA256SUMS; skipping verification"
fi

step 2/3 "Installing"
mkdir -p "$bin_dir" || die "cannot create $bin_dir"
if command -v install >/dev/null 2>&1; then
  install -m 755 "$tmp" "$bin_dir/qbe" || die "cannot install to $bin_dir/qbe"
else
  cp "$tmp" "$bin_dir/qbe" || die "cannot install to $bin_dir/qbe"
  chmod 755 "$bin_dir/qbe"
fi
ok "installed $bin_dir/qbe"

step 3/3 "Shell integration"
if [ "$add_path" -eq 0 ]; then
  info "PATH not modified (--no-path); the binary is at $bin_dir/qbe"
else
  on_path=0
  case ":$PATH:" in *":$bin_dir:"*) on_path=1 ;; esac
  if [ "$on_path" -eq 1 ]; then
    ok "$bin_dir is already on PATH"
  else
    ans=n
    if [ "$assume_yes" -eq 1 ]; then
      ans=y
    elif have_tty; then
      printf 'Add %s to PATH? [Y/n] ' "$bin_dir" >&2
      tty_read
      case "${_ans:-y}" in [Nn]*) ans=n ;; *) ans=y ;; esac
    else
      info "no terminal to ask; add this line to your shell rc to put qbe on PATH:"
      info "  export PATH=\"$bin_dir:\$PATH\""
      ans=n
    fi
    if [ "$ans" = y ]; then
      case "${SHELL##*/}" in
        zsh) rc="$HOME/.zshrc" ;;
        bash) rc="$HOME/.bashrc" ;;
        *) rc="$HOME/.profile" ;;
      esac
      line="export PATH=\"$bin_dir:\$PATH\""
      if [ -f "$rc" ] && grep -qF "$bin_dir" "$rc" 2>/dev/null; then
        ok "PATH entry already present in $rc"
      else
        {
          printf '\n# Added by the qbe.mbt installer\n'
          printf '%s\n' "$line"
        } >>"$rc" || die "cannot update $rc"
        ok "added $bin_dir to $rc"
      fi
      info "this shell: $line"
    else
      info "skipped; qbe is at $bin_dir/qbe"
    fi
  fi
fi

printf '\n%s\n' "${BOLD}${GREEN}qbe is ready.${RESET}" >&2
