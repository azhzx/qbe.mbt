// Build script for the qbe.mbt C-ABI glue layer.
//
// It locates (or builds) the `ir_builder_capi` object produced by MoonBit,
// compiles src/shim.c, then combines the foreign-library object, the MoonBit
// runtime archives and the shim into one self-contained static archive that
// is linked into every target of this crate.
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo = manifest.parent().expect("rust/ has a parent").to_path_buf();
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    let moon_home = env::var("MOON_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(env::var("HOME").unwrap()).join(".moon"));
    let include = moon_home.join("include");
    let moonbitrun = moon_home.join("lib/libmoonbitrun.o");
    let backtrace = moon_home.join("lib/libbacktrace.a");
    let runtime = repo.join("_build/native/debug/build/libruntime.a");

    let capi_obj = locate_capi(&repo);

    // Compile the C shim that bridges MoonBit `Bytes` values.
    let cc = env::var("CC").unwrap_or_else(|_| "cc".to_string());
    let shim_o = out.join("qbe_glue.o");
    let status = Command::new(&cc)
        .arg("-c")
        .arg("-O2")
        .arg("-fPIC")
        .arg("-I")
        .arg(repo.join("include"))
        .arg("-I")
        .arg(&include)
        .arg(manifest.join("src/shim.c"))
        .arg("-o")
        .arg(&shim_o)
        .status()
        .unwrap_or_else(|e| panic!("failed to run {cc}: {e}"));
    assert!(status.success(), "compiling src/shim.c failed");

    // Combine everything into one archive so downstream crates link it too.
    let combined = out.join("libqbe_builder_native.a");
    let _ = std::fs::remove_file(&combined);
    if target_os == "macos" {
        let libtool = env::var("LIBTOOL").unwrap_or_else(|_| "libtool".to_string());
        let status = Command::new(&libtool)
            .arg("-static")
            .arg("-o")
            .arg(&combined)
            .arg(&shim_o)
            .arg(&capi_obj)
            .arg(&moonbitrun)
            .arg(&runtime)
            .arg(&backtrace)
            .status()
            .unwrap_or_else(|e| panic!("failed to run {libtool}: {e}"));
        assert!(
            status.success(),
            "libtool failed to build the combined archive"
        );
    } else {
        combine_with_ar(
            &out,
            &combined,
            &[shim_o, capi_obj, moonbitrun],
            &[runtime, backtrace],
        );
    }

    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=qbe_builder_native");
    println!("cargo:rustc-link-lib=dylib=m");
    println!("cargo:rerun-if-changed=src/shim.c");
    println!("cargo:rerun-if-env-changed=QBE_CAPI_OBJ");
    println!("cargo:rerun-if-env-changed=MOON_HOME");
    println!(
        "cargo:rerun-if-changed={}",
        repo.join("ir_builder").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        repo.join("ir_builder_capi").display()
    );
}

fn locate_capi(repo: &Path) -> PathBuf {
    if let Ok(p) = env::var("QBE_CAPI_OBJ") {
        let p = PathBuf::from(p);
        assert!(p.exists(), "QBE_CAPI_OBJ does not exist: {}", p.display());
        return p;
    }
    let obj = repo
        .join("_build/native/debug/build/ir_builder_capi/__moonbit_link_core__/ir_builder_capi.o");
    if env::var("QBE_NO_MOON_BUILD").is_err() {
        // The compiler emits the object before the (unwanted) executable link
        // that a foreign_library always attempts; tolerate the failure.
        let _ = Command::new("moon")
            .args(["build", "--target", "native", "ir_builder_capi"])
            .current_dir(repo)
            .status();
    }
    if obj.exists() {
        return obj;
    }
    if let Some(p) = search(&repo.join("_build"), "ir_builder_capi.o") {
        return p;
    }
    panic!(
        "could not find ir_builder_capi.o; run `moon build --target native ir_builder_capi` or set QBE_CAPI_OBJ"
    );
}

fn search(dir: &Path, name: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(p) = search(&path, name) {
                return Some(p);
            }
        } else if path.file_name().map(|n| n == name).unwrap_or(false) {
            return Some(path);
        }
    }
    None
}

fn combine_with_ar(out: &Path, combined: &Path, objects: &[PathBuf], archives: &[PathBuf]) {
    let extract = out.join("extract");
    let _ = std::fs::remove_dir_all(&extract);
    std::fs::create_dir_all(&extract).unwrap();
    let ar = env::var("AR").unwrap_or_else(|_| "ar".to_string());
    let mut members: Vec<PathBuf> = objects.to_vec();
    for a in archives {
        let status = Command::new(&ar)
            .arg("x")
            .arg(a)
            .current_dir(&extract)
            .status()
            .unwrap();
        assert!(status.success(), "ar x {}", a.display());
    }
    for entry in std::fs::read_dir(&extract).unwrap().flatten() {
        let p = entry.path();
        if p.extension().map(|e| e == "o").unwrap_or(false) {
            members.push(p);
        }
    }
    let _ = std::fs::remove_file(combined);
    let status = Command::new(&ar)
        .arg("rcs")
        .arg(combined)
        .args(&members)
        .status()
        .unwrap();
    assert!(status.success(), "ar rcs failed");
}
