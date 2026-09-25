//! Debug metadata: the front end's view of a debug variable's language type.
//!
//! QBE IL only carries word/long/single/double classes, so the type must come
//! from the front end (the same split Cranelift uses). Enable debug info on the
//! module, then declare variables with `FunctionBuilder::declare_var`.

/// A language type for a debug variable.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DebugType {
    /// 32-bit integer.
    W,
    /// 64-bit integer.
    L,
    /// Single-precision float.
    S,
    /// Double-precision float.
    D,
    /// Pointer (`void*`).
    Ptr,
    /// Aggregate with a name and byte size.
    Agg(String, u32),
}
