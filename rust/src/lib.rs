//! Rust glue layer over the qbe.mbt programmatic QBE IL builder.
//!
//! The API mirrors Cranelift/inkwell: a Context creates a Module, functions
//! are declared with a Signature, and a FunctionBuilder emits instructions via
//! builder.ins(). The resulting module can be printed back to QBE IL, emitted
//! as arm64 assembly, or emitted as a self-contained Mach-O arm64 object.
//!
//! ```no_run
//! use qbe_builder::{Context, Signature, Type};
//!
//! let ctx = Context::new();
//! let mut module = ctx.create_module();
//! let f = module.add_function("add", Signature::new([Type::I32, Type::I32], Some(Type::I32)));
//! {
//!     let mut b = module.builder(f);
//!     let a = b.params()[0];
//!     let c = b.params()[1];
//!     let r = b.ins().iadd(a, c);
//!     b.ins().return_(&[r]);
//! }
//! let il = module.emit_il();
//! assert!(il.contains("export function w $add"));
//! ```

mod builder;
mod ffi;
mod module;
pub mod types;

pub use builder::{BlockId, FunctionBuilder, InstructionInserter, Value};
pub use module::{Context, Error, FunctionId, Module};
pub use types::{FloatCC, IntCC, Signature, Type};
