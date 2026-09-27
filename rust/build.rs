// Build script for the `qopple` crate.
//
// There are two ways to obtain the native half of the C ABI:
//
//   * **Vendored archives (default for crates.io builds).** The crate ships a
//     self-contained static archive per supported target under
//     `vendor/<target-triple>/libqopple_native.a`. These are produced by the
//     `crates` GitHub Actions workflow with the MoonBit toolchain, so a
//     downstream `cargo build` only has to link one file and needs neither
//     `moon` nor the qbe.mbt repository.
//
//   * **From source.** Inside a qbe.mbt checkout (or with
//     `QOPPLE_BUILD_FROM_SOURCE=1`), build `ir_builder_capi` with `moon`,
//     compile `src/shim.c`, and combine the foreign-library object, the MoonBit
//     runtime archives and the shim into the same archive. This is what keeps
//     `cargo test` inside the repository working against live MoonBit sources.
//
// Supported prebuilt targets: aarch64-apple-darwin, x86_64-unknown-linux-gnu,
// aarch64-unknown-linux-gnu.
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    let repo = manifest.parent().map(Path::to_path_buf);

    let force_source = env::var_os("QOPPLE_BUILD_FROM_SOURCE").is_some();
    let have_repo = repo
        .as_deref()
        .map(|r| r.join("ir_builder_capi/moon.pkg").exists())
        .unwrap_or(false);

    // A repository checkout always builds from source so that changes to the
    // MoonBit side are picked up; the published crate has no repository next to
    // it and therefore uses the vendored archive.
    if !force_source && !have_repo {
        let triple = target_triple(&target_arch, &target_os);
        let dir = manifest.join("vendor").join(triple);
        let archive = dir.join("libqopple_native.a");
        if !archive.exists() {
            panic!(
                "qopple: no prebuilt native library for {triple}\n\
                 Looked in {}\n\
                 Supported prebuilt targets: aarch64-apple-darwin, \
                 x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu.\n\
                 Install the MoonBit toolchain (https://www.moonbitlang.com) and \
                 build a qbe.mbt checkout with QOPPLE_BUILD_FROM_SOURCE=1 to \
                 build this target from source.",
                archive.display()
            );
        }
        println!("cargo:rustc-link-search=native={}", dir.display());
        println!("cargo:rustc-link-lib=static=qopple_native");
        link_system_libs(&target_os);
        println!("cargo:rerun-if-changed={}", archive.display());
        return;
    }

    let repo = repo.expect("a from-source build needs the qbe.mbt repository next to rust/");
    build_from_source(&repo, &manifest, &out, &target_os);
}

fn target_triple(arch: &str, os: &str) -> &'static str {
    match (arch, os) {
        ("aarch64", "macos") => "aarch64-apple-darwin",
        ("x86_64", "linux") => "x86_64-unknown-linux-gnu",
        ("aarch64", "linux") => "aarch64-unknown-linux-gnu",
        _ => panic!("qopple: unsupported target {arch}-{os}"),
    }
}

fn link_system_libs(target_os: &str) {
    // The MoonBit runtime uses the C math library; everything else comes from
    // libSystem on macOS and from libc/libgcc on Linux.
    println!("cargo:rustc-link-lib=dylib=m");
    if target_os == "linux" {
        println!("cargo:rustc-link-lib=dylib=pthread");
    }
}

fn build_from_source(repo: &Path, manifest: &Path, out: &Path, target_os: &str) {
    let moon_home = env::var("MOON_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(env::var("HOME").unwrap()).join(".moon"));
    let include = moon_home.join("include");
    let moonbitrun = moon_home.join("lib/libmoonbitrun.o");
    let backtrace = moon_home.join("lib/libbacktrace.a");
    let capi_obj = locate_capi(repo);
    let run_asm_stub = repo.join("_build/native/debug/build/native/native_stub.o");
    assert!(
        run_asm_stub.exists(),
        "missing {}; the JIT C ABI links native's stub",
        run_asm_stub.display()
    );

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

    // The MoonBit runtime archive is optional: some build trees do not produce
    // it, and the runtime entry points are already provided by libmoonbitrun.o
    // and the native stub (libtool silently ignores a missing input, so this was
    // only ever fatal on the `ar` path).
    let mut archives: Vec<PathBuf> = Vec::new();
    match locate_runtime(repo) {
        Some(rt) => archives.push(rt),
        None => println!(
            "cargo:warning=qbe.mbt: libruntime.a not found under _build; \
             continuing without it"
        ),
    }
    archives.push(backtrace);

    // Combine everything into one archive so downstream crates link it too.
    let combined = out.join("libqopple_native.a");
    let _ = std::fs::remove_file(&combined);
    let objects = [shim_o, capi_obj, run_asm_stub, moonbitrun];
    if target_os == "macos" {
        let libtool = env::var("LIBTOOL").unwrap_or_else(|_| "libtool".to_string());
        let mut cmd = Command::new(&libtool);
        cmd.arg("-static").arg("-o").arg(&combined);
        for path in objects.iter().chain(archives.iter()) {
            cmd.arg(path);
        }
        let status = cmd
            .status()
            .unwrap_or_else(|e| panic!("failed to run {libtool}: {e}"));
        assert!(
            status.success(),
            "libtool failed to build the combined archive"
        );
    } else {
        combine_with_ar(out, &combined, &objects, &archives);
    }

    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=qopple_native");
    link_system_libs(target_os);
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
    println!("cargo:rerun-if-changed={}", repo.join("native").display());
}

fn locate_runtime(repo: &Path) -> Option<PathBuf> {
    let build = repo.join("_build/native/debug/build");
    let plain = build.join("libruntime.a");
    if plain.exists() {
        return Some(plain);
    }
    // Newer toolchains may fingerprint the archive name.
    if let Ok(entries) = std::fs::read_dir(&build) {
        let mut hits: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .map(|n| {
                        let n = n.to_string_lossy();
                        n.starts_with("libruntime") && n.ends_with(".a")
                    })
                    .unwrap_or(false)
            })
            .collect();
        hits.sort();
        if let Some(p) = hits.into_iter().next() {
            return Some(p);
        }
    }
    None
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
    // Some toolchains name the foreign-library object differently (for example
    // ir_builder_capi.core.o); accept any object that carries the package name.
    if let Some(p) = search_name(&repo.join("_build"), "ir_builder_capi", ".o") {
        return p;
    }
    panic!(
        "could not find ir_builder_capi.o; run `moon build --target native ir_builder_capi` or set QBE_CAPI_OBJ"
    );
}

fn search_name(dir: &Path, contains: &str, suffix: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(p) = search_name(&path, contains, suffix) {
                return Some(p);
            }
        } else if let Some(name) = path.file_name() {
            let name = name.to_string_lossy();
            if name.contains(contains) && name.ends_with(suffix) {
                return Some(path);
            }
        }
    }
    None
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
