#!/usr/bin/env bash
# Build and run the Rust QBE-IL builder demo (demo/13_builder_rust).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec cargo run --quiet --manifest-path demo/13_builder_rust/Cargo.toml