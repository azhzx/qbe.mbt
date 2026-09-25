#!/usr/bin/env sh
# qbe.mbt installer / bootstrap (macOS and Linux).
#
# Interactive by default (rustup-style); use --yes for non-interactive runs.

set -eu

# ------------------------------------------------------------ pretty output
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  BOLD=$(printf '\033[1m')
  DIM=$(printf '\033[2m')
  RED=$(printf '\033[31m')
  GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m')
  CYAN=$(printf '\033[36m')
  RESET=$(printf '\033[0m')
else
  BOLD= DIM= RED= GREEN= YELLOW= CYAN= RESET=
fi

step() { printf '\n%s\n' "${BOLD}${CYAN}[$1] $2${RESET}"; }
ok() { printf '%s\n' "${GREEN}ok${RESET}  $*"; }
info() { printf '%s\n' "${DIM}    $*${RESET}"; }
warn() { printf '%s\n' "${YELLOW}!!${RESET}  $*" >&2; }
die() { printf '%s\n' "${RED}xx${RESET}  $*" >&2; exit 1; }

banner() {
  printf '%s\n' "${BOLD}${CYAN}"
  printf '%s\n' "  +--------------------------------------------+"
  printf '%s\n' "  |  qbe.mbt - QBE reimplemented in MoonBit    |"
  printf '%s\n' "  +--------------------------------------------+"
  printf '%s\n' "${RESET}"
}

ask_yn() { # ask_yn QUESTION DEFAULT(y|n)
  _q=$1
  _def=${2:-n}
  if [ "$assume_yes" -eq 1 ]; then
    [ "$_def" = y ]
    return $?
  fi
  if [ "$_def" = y ]; then _hint="Y/n"; else _hint="y/N"; fi
  printf '%s %s[%s]%s ' "$_q" "$DIM" "$_hint" "$RESET"
  read -r _ans || _ans=
  case "$_ans" in
    y | Y | yes | YES) return 0 ;;
    n | N | no | NO) return 1 ;;
    *) [ "$_def" = y ] && return 0 || return 1 ;;
  esac
}

# ----------------------------------------------------------------- options
moon_arg=
want_install=0
skip_install=0
with_reference=0
add_path=1
assume_yes=0
bin_dir="${HOME}/.local/bin"

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap.sh [options]

  --moon PATH       Use the MoonBit compiler at PATH.
  --install-moon    Install the MoonBit compiler.
  --skip-install    Never install the MoonBit compiler.
  --bin-dir DIR     Where to install the qbe binary (default: ~/.local/bin).
  --no-path         Do not offer to add qbe to PATH.
  --with-reference  Also init and build vendor/qbe (differential reference).
  --yes, -y         Assume "yes"; never prompt.
  --help, -h        Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --moon)
      [ $# -ge 2 ] || die "--moon needs a path"
      moon_arg=$2
      shift 2
      ;;
    --bin-dir)
      [ $# -ge 2 ] || die "--bin-dir needs a directory"
      bin_dir=$2
      shift 2
      ;;
    --install-moon) want_install=1; shift ;;
    --skip-install) skip_install=1; shift ;;
    --with-reference) with_reference=1; shift ;;
    --no-path) add_path=0; shift ;;
    --yes | -y) assume_yes=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# -------------------------------------------------------------- step 1: moon
moon_cmd=

find_moon() {
  if command -v moon >/dev/null 2>&1; then
    command -v moon
  elif [ -x "$HOME/.moon/bin/moon" ]; then
    printf '%s' "$HOME/.moon/bin/moon"
  fi
}

# Official Unix installers. The .cn mirror is primary (the one the MoonBit
# docs use); .com is a fallback for networks where .cn is unreachable (e.g.
# GitHub runners). MOON_INSTALL_URL overrides the whole list.
moon_install_urls="${MOON_INSTALL_URL:-https://cli.moonbitlang.cn/install/unix.sh https://cli.moonbitlang.com/install/unix.sh}"

install_from_mirror() {
  _url=$1
  _script=$(mktemp)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 -o "$_script" "$_url" || {
      rm -f "$_script"
      return 1
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=15 -O "$_script" "$_url" || {
      rm -f "$_script"
      return 1
    }
  else
    die "curl or wget is required to install MoonBit"
  fi
  bash "$_script"
  _rc=$?
  rm -f "$_script"
  return $_rc
}

install_moon() {
  case "$(uname -s)" in
    Darwin | Linux) ;;
    *) die "unsupported operating system; install MoonBit manually" ;;
  esac
  _installed=0
  for _url in $moon_install_urls; do
    info "curl -fsSL $_url | bash"
    if install_from_mirror "$_url"; then
      _installed=1
      break
    fi
  done
  [ "$_installed" -eq 1 ] || die "MoonBit installation failed from all mirrors"
  moon_cmd=$(find_moon)
  [ -n "$moon_cmd" ] ||
    die "MoonBit was installed but 'moon' is not on PATH yet; open a new shell and retry"
}

custom_moon() {
  printf '  Path to the moon executable: '
  read -r _p || _p=
  [ -n "$_p" ] || die "no path given"
  [ -x "$_p" ] || die "'$_p' is not executable"
  "$_p" version >/dev/null 2>&1 || die "'$_p' does not look like the MoonBit compiler"
  moon_cmd=$_p
}

choose_moon() {
  _found=$(find_moon)
  printf '%s\n' "How should we get the MoonBit compiler?"
  if [ -n "$_found" ]; then
    printf '  %s1)%s  Use the moon on PATH      %s(%s)%s\n' "$CYAN" "$RESET" "$DIM" "$_found" "$RESET"
  else
    printf '  %s1)%s  Use the moon on PATH      %s(not found)%s\n' "$DIM" "$RESET" "$DIM" "$RESET"
  fi
  printf '  %s2)%s  Install MoonBit           %s(Homebrew / install.sh)%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
  printf '  %s3)%s  Use a custom moon path\n' "$CYAN" "$RESET"
  if [ -n "$_found" ]; then _def=1; else _def=2; fi
  printf '  Choose %s[%s]%s: ' "$DIM" "$_def" "$RESET"
  if [ "$assume_yes" -eq 1 ]; then
    _choice=$_def
    printf '\n'
  else
    read -r _choice || _choice=
    [ -n "$_choice" ] || _choice=$_def
  fi
  case "$_choice" in
    1)
      [ -n "$_found" ] || die "no moon on PATH; choose 2 or 3"
      moon_cmd=$_found
      ;;
    2) install_moon ;;
    3) custom_moon ;;
    *) die "invalid choice: $_choice" ;;
  esac
  ok "using $moon_cmd"
}

# ----------------------------------------------------------- step 2: build
find_binary() {
  for _p in \
    _build/native/debug/build/cmd/main/main.exe \
    _build/native/release/build/cmd/main/main.exe \
    target/native/debug/build/cmd/main/main.exe; do
    if [ -f "$_p" ]; then
      printf '%s' "$_p"
      return 0
    fi
  done
  _f=$(find _build target -name 'main.exe' -path '*cmd/main*' 2>/dev/null | head -n 1 || true)
  [ -n "$_f" ] && printf '%s' "$_f"
  return 0
}

# ------------------------------------------------------------ step 3: PATH
install_binary() {
  _bin=$1
  mkdir -p "$bin_dir" || die "cannot create $bin_dir"
  cp "$_bin" "$bin_dir/qbe" || die "cannot install to $bin_dir/qbe"
  chmod +x "$bin_dir/qbe"
  ok "installed $bin_dir/qbe"
  case ":$PATH:" in
    *":$bin_dir:"*)
      ok "$bin_dir is already on your PATH"
      return 0
      ;;
  esac
  case "${SHELL##*/}" in
    zsh) _rc="$HOME/.zshrc" ;;
    bash) _rc="$HOME/.bashrc" ;;
    *) _rc="$HOME/.profile" ;;
  esac
  _line="export PATH=\"$bin_dir:\$PATH\""
  if [ -f "$_rc" ] && grep -qF "$bin_dir" "$_rc"; then
    ok "PATH entry already present in $_rc"
  else
    {
      printf '\n# Added by the qbe.mbt installer\n'
      printf '%s\n' "$_line"
    } >>"$_rc" || die "cannot update $_rc"
    ok "added $bin_dir to $_rc"
  fi
  printf '\n%sRun %s%s%s%s to use qbe in this shell.\n' \
    "$DIM" "$RESET" "$BOLD" "$_line" "$RESET"
}

# ------------------------------------------------------------------- main
banner

step "1/3" "MoonBit compiler"
if [ -n "$moon_arg" ]; then
  [ -x "$moon_arg" ] || die "'$moon_arg' is not executable"
  moon_cmd=$moon_arg
  ok "using $moon_cmd"
elif [ "$want_install" -eq 1 ]; then
  install_moon
  ok "using $moon_cmd"
elif [ "$skip_install" -eq 1 ]; then
  moon_cmd=$(find_moon)
  [ -n "$moon_cmd" ] || die "no moon on PATH (and --skip-install was given)"
  ok "using $moon_cmd"
else
  choose_moon
fi

step "2/3" "Building qbe"
info "$moon_cmd build --target native"
"$moon_cmd" build --target native || die "moon build failed"
qbe_bin=$(find_binary)
[ -n "$qbe_bin" ] || die "could not find the built binary under _build/native"
"$qbe_bin" --help >/dev/null 2>&1 || warn "the built binary did not respond to --help"
ok "built $qbe_bin"

if [ "$with_reference" -eq 1 ]; then
  info "initializing and building vendor/qbe (reference)"
  git submodule update --init --recursive vendor/qbe || die "could not init vendor/qbe"
  (cd vendor/qbe && make) || die "vendor/qbe build failed"
  ok "vendor/qbe built"
fi

step "3/3" "Shell integration"
if [ "$add_path" -eq 0 ]; then
  info "skipped (--no-path); the binary is at $qbe_bin"
elif ask_yn "Add qbe to your PATH (install to $bin_dir)" y; then
  install_binary "$qbe_bin"
else
  info "skipped; the binary is at $qbe_bin"
  info "to install later: mkdir -p $bin_dir && cp $qbe_bin $bin_dir/qbe"
fi

printf '\n%s\n' "${BOLD}${GREEN}qbe.mbt is ready.${RESET}"
