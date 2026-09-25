//! In-memory JIT: resolve functions and globals in a mapped code image.

use crate::ffi;
use crate::module::{last_error_now, Error};

/// A JIT-loaded module (one JIT handle).
///
/// It does not hold the builder lock: the code image is independent of the
/// builder. As for the builder, use it from a single thread.
pub struct JitModule {
    handle: i64,
}

impl JitModule {
    pub(crate) fn from_handle(handle: i64) -> JitModule {
        JitModule { handle }
    }

    /// Resolve a function to its entry address.
    pub fn symbol(&self, name: &str) -> Result<usize, Error> {
        let addr = ffi::with_bytes(name.as_bytes(), |nb| unsafe {
            ffi::qbe_jit_symbol(self.handle, nb)
        });
        if addr == 0 {
            Err(last_error_now())
        } else {
            Ok(addr as usize)
        }
    }

    /// Look up a function and transmute its address to a function pointer
    /// (Cranelift-style get_finalized_function).
    ///
    /// The caller must pick the correct signature, for example
    /// `extern "C" fn(i32, i32) -> i32`.
    pub fn get_fn<F: Copy>(&self, name: &str) -> Result<F, Error> {
        let addr = self.symbol(name)?;
        assert_eq!(
            std::mem::size_of::<F>(),
            std::mem::size_of::<usize>(),
            "get_fn requires a function pointer type",
        );
        Ok(unsafe { std::mem::transmute_copy(&addr) })
    }

    /// Resolve a global (data symbol) to its address.
    pub fn get_data_ptr(&self, name: &str) -> Result<*mut u8, Error> {
        let addr = ffi::with_bytes(name.as_bytes(), |nb| unsafe {
            ffi::qbe_jit_global(self.handle, nb)
        });
        if addr == 0 {
            Err(last_error_now())
        } else {
            Ok(addr as *mut u8)
        }
    }
}

impl Drop for JitModule {
    fn drop(&mut self) {
        unsafe { ffi::qbe_jit_free(self.handle) };
    }
}
