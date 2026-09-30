//! Run the `qbe` executable from the [qbe.mbt](https://github.com/azhzx/qbe.mbt)
//! project as a subprocess.
//!
//! This is the pure-Rust companion to the [`qopple`](https://crates.io/crates/qopple)
//! crate: it links nothing at build time and instead locates the compiler at
//! runtime. Install the binary with the qbe.mbt installer
//! (`curl -fsSL https://i2pl.com/install-qbe-mbt.sh | sh`) or build it from a
//! checkout, then point this crate at it via `$QOPPLE_BIN` or `PATH`.
//!
//! ```no_run
//! use qopple_cli::Qbe;
//!
//! let qbe = Qbe::find()?;
//! let asm = qbe.emit_asm("input.ssa", Some("arm64"))?;
//! println!("{asm}");
//! # Ok::<(), qopple_cli::Error>(())
//! ```

use std::ffi::OsStr;
use std::fmt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

/// Environment variable that overrides the executable location.
pub const BIN_ENV: &str = "QOPPLE_BIN";

/// Failure to locate or run the compiler.
#[derive(Debug)]
pub enum Error {
    /// No `qbe` executable was found.
    NotFound,
    /// The process could not be started.
    Io(std::io::Error),
    /// The compiler exited with a non-zero status.
    Failed {
        /// Exit code, when the process exited rather than being signalled.
        code: Option<i32>,
        /// Captured standard error.
        stderr: String,
    },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::NotFound => write!(
                f,
                "could not find the `qbe` executable; install it from \
                 https://i2pl.com/install-qbe-mbt.sh or set {BIN_ENV}"
            ),
            Error::Io(e) => write!(f, "failed to run qbe: {e}"),
            Error::Failed { code, stderr } => {
                write!(f, "qbe exited with status {code:?}: {}", stderr.trim())
            }
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io(e) => Some(e),
            _ => None,
        }
    }
}

/// Result alias for this crate.
pub type Result<T> = std::result::Result<T, Error>;

/// A handle to the `qbe` executable.
#[derive(Debug, Clone)]
pub struct Qbe {
    bin: PathBuf,
}

impl Qbe {
    /// Use an explicit executable path.
    pub fn new(bin: impl Into<PathBuf>) -> Self {
        Self { bin: bin.into() }
    }

    /// Locate the compiler: `$QOPPLE_BIN`, then `qbe` on `PATH`, then
    /// `~/.local/bin/qbe` (the installer's default prefix).
    pub fn find() -> Result<Self> {
        if let Some(p) = std::env::var_os(BIN_ENV) {
            let p = PathBuf::from(p);
            if p.is_file() {
                return Ok(Self::new(p));
            }
        }
        if let Some(p) = find_in_path("qbe") {
            return Ok(Self::new(p));
        }
        if let Some(home) = home_dir() {
            let p = home.join(".local/bin/qbe");
            if p.is_file() {
                return Ok(Self::new(p));
            }
        }
        Err(Error::NotFound)
    }

    /// The executable path.
    pub fn binary(&self) -> &Path {
        &self.bin
    }

    /// A `Command` pre-configured with the executable and piped output.
    pub fn command(&self) -> Command {
        let mut c = Command::new(&self.bin);
        c.stdout(std::process::Stdio::piped());
        c.stderr(std::process::Stdio::piped());
        c
    }

    /// Run the compiler with `args`, returning its raw output. A non-zero
    /// exit status is *not* an error here.
    pub fn output<I, S>(&self, args: I) -> Result<Output>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        self.command().args(args).output().map_err(Error::Io)
    }

    /// Run the compiler with `args`, turning a non-zero exit status into
    /// `Error::Failed`.
    pub fn check<I, S>(&self, args: I) -> Result<Output>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let out = self.output(args)?;
        if out.status.success() {
            Ok(out)
        } else {
            Err(Error::Failed {
                code: out.status.code(),
                stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
            })
        }
    }

    /// Compile `ssa` and return the emitted assembly as text. `target` is
    /// one of `amd64_sysv` (default), `arm64`, `rv64`, `la64` or `wasm`.
    pub fn emit_asm(&self, ssa: impl AsRef<Path>, target: Option<&str>) -> Result<String> {
        let mut args: Vec<String> = Vec::new();
        if let Some(t) = target {
            args.push("-t".to_string());
            args.push(t.to_string());
        }
        args.push(ssa.as_ref().to_string_lossy().into_owned());
        let out = self.check(args)?;
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    }

    /// Interpret `ssa` directly, calling `func_and_args` (for example
    /// `adiff,20,22`) through `--run`.
    pub fn run_ssa(&self, ssa: impl AsRef<Path>, func_and_args: &str) -> Result<Output> {
        self.check([
            "--run".to_string(),
            func_and_args.to_string(),
            ssa.as_ref().to_string_lossy().into_owned(),
        ])
    }

    /// Compile `ssa` to in-process machine code and call `func_and_args`
    /// through `--jit` (macOS aarch64 hosts only).
    pub fn jit_ssa(&self, ssa: impl AsRef<Path>, func_and_args: &str) -> Result<Output> {
        self.check([
            "--jit".to_string(),
            func_and_args.to_string(),
            ssa.as_ref().to_string_lossy().into_owned(),
        ])
    }
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(name))
        .find(|p| p.is_file())
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_binary_is_an_io_error() {
        let qbe = Qbe::new("/nonexistent/qbe-does-not-exist");
        assert!(matches!(qbe.check(["--help"]), Err(Error::Io(_))));
    }

    #[test]
    fn explicit_path_is_reported() {
        let qbe = Qbe::new("/usr/bin/env");
        assert_eq!(qbe.binary(), Path::new("/usr/bin/env"));
    }
}
