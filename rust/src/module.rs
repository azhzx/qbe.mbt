//! Context, module and error types.

use crate::builder::{FunctionBuilder, Value};
use crate::ffi;
use crate::jit::JitModule;
use crate::types::{Signature, Type};
use std::sync::{Mutex, MutexGuard, Once};

static INIT: Once = Once::new();

// The qbe_* C ABI keeps a process-global builder registry and the MoonBit
// runtime is not thread-safe, so every live Module holds this lock. This also
// makes Module !Send.
static LOCK: Mutex<()> = Mutex::new(());

/// Initialize the MoonBit runtime and the builder module exactly once.
pub(crate) fn ensure_init() {
    INIT.call_once(|| unsafe { ffi::qbe_glue_init() });
}

/// An error reported by the builder or by emission.
#[derive(Debug, Clone)]
pub struct Error {
    message: String,
}

impl Error {
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for Error {}

/// The compilation context. In this binding it only guarantees runtime
/// initialization; it mirrors the Cranelift/inkwell entry point.
#[derive(Debug, Default)]
pub struct Context {
    _private: (),
}

impl Context {
    pub fn new() -> Context {
        ensure_init();
        Context { _private: () }
    }

    /// Create a new module (one MoonBit IR builder).
    pub fn create_module(&self) -> Module {
        Module::new()
    }
}

/// A handle to a function inside a module.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct FunctionId(pub(crate) usize);

pub(crate) struct FuncMeta {
    pub name: String,
    pub sig: Signature,
    pub fid: ffi::Func,
    pub params: Vec<Value>,
}

/// A QBE module: owns one MoonBit builder handle.
pub struct Module {
    pub(crate) handle: ffi::Builder,
    pub(crate) funcs: Vec<FuncMeta>,
    compiled: bool,
    _guard: MutexGuard<'static, ()>,
}

impl Module {
    pub fn new() -> Module {
        ensure_init();
        let guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let handle = unsafe { ffi::qbe_builder_new() };
        assert!(handle > 0, "qbe_builder_new returned an invalid handle");
        Module {
            handle,
            funcs: Vec::new(),
            compiled: false,
            _guard: guard,
        }
    }

    /// Define an exported function (inkwell-style `add_function`).
    pub fn add_function(&mut self, name: &str, sig: Signature) -> FunctionId {
        self.add_function_with(name, sig, true)
    }

    /// Define a function, choosing whether it is exported.
    pub fn add_function_with(&mut self, name: &str, sig: Signature, export: bool) -> FunctionId {
        let mut packed = Vec::with_capacity(sig.params.len() * 4);
        for t in &sig.params {
            packed.extend_from_slice(&t.code().to_le_bytes());
        }
        let ret_cls = sig.ret.map(Type::code).unwrap_or(ffi::QBE_VOID);
        let fid = ffi::with_bytes(name.as_bytes(), |nb| {
            ffi::with_bytes(&packed, |pb| unsafe {
                ffi::qbe_add_func(self.handle, nb, ret_cls, export as i32, pb)
            })
        });
        assert!(fid >= 0, "qbe_add_func failed: {}", self.last_error());
        let mut params = Vec::with_capacity(sig.params.len());
        for (i, t) in sig.params.iter().enumerate() {
            let id = unsafe { ffi::qbe_func_param(self.handle, fid, i as i32) };
            params.push(Value::new(id, *t));
        }
        self.funcs.push(FuncMeta {
            name: name.to_string(),
            sig,
            fid,
            params,
        });
        FunctionId(self.funcs.len() - 1)
    }

    /// Position a builder on a function (Cranelift-style).
    pub fn builder(&mut self, f: FunctionId) -> FunctionBuilder<'_> {
        assert!(!self.compiled, "module already compiled");
        FunctionBuilder::new(self, f)
    }

    /// Append a data section holding a UTF-8 string (as one b "..." item).
    pub fn data_string(&mut self, name: &str, export: bool, s: &str) {
        ffi::with_bytes(name.as_bytes(), |nb| {
            ffi::with_bytes(s.as_bytes(), |sb| unsafe {
                ffi::qbe_data_string(self.handle, nb, export as i32, sb)
            })
        });
    }

    /// Append a data section holding raw bytes (one b item per byte).
    pub fn data_bytes(&mut self, name: &str, export: bool, data: &[u8]) {
        ffi::with_bytes(name.as_bytes(), |nb| {
            ffi::with_bytes(data, |db| unsafe {
                ffi::qbe_data_bytes(self.handle, nb, export as i32, db)
            })
        });
    }

    /// Serialize the module back to QBE IL text.
    pub fn emit_il(&self) -> String {
        let b = unsafe { ffi::qbe_emit_il(self.handle) };
        String::from_utf8_lossy(&ffi::take_bytes(b)).into_owned()
    }

    /// Enable or disable DWARF debug info in the emitted assembly.
    pub fn enable_debug_info(&mut self, on: bool) {
        unsafe { ffi::qbe_dbg_enable(on as i32) };
    }

    /// Set the compilation-unit name and directory used by debug info.
    pub fn dbg_compile_unit(&mut self, name: &str, dir: &str) {
        ffi::with_bytes(name.as_bytes(), |nb| {
            ffi::with_bytes(dir.as_bytes(), |db| unsafe {
                ffi::qbe_dbg_compile_unit(self.handle, nb, db)
            })
        });
    }

    /// Declare a debug variable bound to `value` in function `f`.
    pub fn dbg_var(
        &mut self,
        f: FunctionId,
        name: &str,
        ty: crate::debug::DebugType,
        value: Value,
    ) {
        let fid = self.funcs[f.0].fid;
        let (code, tname, size) = match ty {
            crate::debug::DebugType::W => (0, String::new(), 0),
            crate::debug::DebugType::L => (1, String::new(), 0),
            crate::debug::DebugType::S => (2, String::new(), 0),
            crate::debug::DebugType::D => (3, String::new(), 0),
            crate::debug::DebugType::Ptr => (4, String::new(), 0),
            crate::debug::DebugType::Agg(n, s) => (5, n, s as i32),
        };
        ffi::with_bytes(name.as_bytes(), |nb| {
            ffi::with_bytes(tname.as_bytes(), |tb| unsafe {
                ffi::qbe_dbg_var(self.handle, fid, nb, code, tb, size, value.id())
            })
        });
    }

    /// Emit arm64 assembly text.
    pub fn emit_asm(&mut self) -> Result<String, Error> {
        let b = unsafe { ffi::qbe_emit_asm(self.handle) };
        let v = ffi::take_bytes(b);
        if v.is_empty() {
            Err(self.last_error())
        } else {
            self.compiled = true;
            Ok(String::from_utf8_lossy(&v).into_owned())
        }
    }

    /// Emit arm64 assembly for a gas flavor ("e" ELF, "m" Mach-O).
    pub fn emit_asm_with_gas(&mut self, gas: &str) -> Result<String, Error> {
        let b = ffi::with_bytes(gas.as_bytes(), |gb| unsafe {
            ffi::qbe_emit_asm_gas(self.handle, gb)
        });
        let v = ffi::take_bytes(b);
        if v.is_empty() {
            Err(self.last_error())
        } else {
            self.compiled = true;
            Ok(String::from_utf8_lossy(&v).into_owned())
        }
    }

    /// Emit a self-contained Mach-O arm64 object.
    pub fn emit_object(&mut self) -> Result<Vec<u8>, Error> {
        let b = unsafe { ffi::qbe_emit_object(self.handle) };
        let v = ffi::take_bytes(b);
        if v.is_empty() {
            Err(self.last_error())
        } else {
            self.compiled = true;
            Ok(v)
        }
    }

    pub(crate) fn last_error(&self) -> Error {
        last_error_now()
    }

    /// Compile the module to a self-contained code image, map it executable and
    /// return a JIT module that resolves functions by name.
    ///
    /// This consumes the IR (the backend passes run once), so call it after
    /// emit_il / emit_asm.
    pub fn jit(&mut self) -> Result<JitModule, Error> {
        self.jit_with_symbols(&[])
    }

    /// Like jit, but resolves the given host callback symbols first (name to
    /// function address), falling back to dlsym for the rest.
    pub fn jit_with_symbols(&mut self, symbols: &[(&str, usize)]) -> Result<JitModule, Error> {
        unsafe { ffi::qbe_jit_symbol_clear() };
        for (name, addr) in symbols {
            ffi::with_bytes(name.as_bytes(), |nb| unsafe {
                ffi::qbe_jit_symbol_define(nb, *addr as i64)
            });
        }
        let h = unsafe { ffi::qbe_jit_load(self.handle) };
        unsafe { ffi::qbe_jit_symbol_clear() };
        if h <= 0 {
            Err(self.last_error())
        } else {
            self.compiled = true;
            Ok(JitModule::from_handle(h))
        }
    }
}

impl Drop for Module {
    fn drop(&mut self) {
        unsafe { ffi::qbe_builder_free(self.handle) };
    }
}

pub(crate) fn last_error_now() -> Error {
    let mut buf = vec![0u8; 4096];
    let n = unsafe { ffi::qbe_glue_error_copy(buf.as_mut_ptr(), buf.len()) };
    buf.truncate(n.min(buf.len()));
    Error {
        message: String::from_utf8_lossy(&buf).into_owned(),
    }
}
