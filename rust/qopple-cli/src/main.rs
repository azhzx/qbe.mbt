//! Launcher that forwards its arguments to the qbe.mbt compiler.
//!
//! It resolves the executable the same way the `qopple-cli` library does
//! (`$QOPPLE_BIN`, then `PATH`, then `~/.local/bin/qbe`).

use std::process::{Command, ExitCode};

use qopple_cli::Qbe;

fn main() -> ExitCode {
    let qbe = match Qbe::find() {
        Ok(qbe) => qbe,
        Err(e) => {
            eprintln!("qopple: {e}");
            return ExitCode::FAILURE;
        }
    };
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    match Command::new(qbe.binary()).args(&args).status() {
        Ok(status) => ExitCode::from(status.code().unwrap_or(1).clamp(0, 255) as u8),
        Err(e) => {
            eprintln!("qopple: {}: {e}", qbe.binary().display());
            ExitCode::FAILURE
        }
    }
}
