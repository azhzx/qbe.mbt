//! QBE scalar types, condition codes and function signatures.

use crate::ffi;

/// A QBE scalar class.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Type {
    I32,
    I64,
    F32,
    F64,
}

impl Type {
    pub(crate) fn code(self) -> i32 {
        match self {
            Type::I32 => ffi::QBE_W,
            Type::I64 => ffi::QBE_L,
            Type::F32 => ffi::QBE_S,
            Type::F64 => ffi::QBE_D,
        }
    }

    pub fn is_float(self) -> bool {
        matches!(self, Type::F32 | Type::F64)
    }
}

/// Integer comparison condition (Cranelift-style).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IntCC {
    Equal,
    NotEqual,
    SignedLessThan,
    SignedLessThanOrEqual,
    SignedGreaterThan,
    SignedGreaterThanOrEqual,
    UnsignedLessThan,
    UnsignedLessThanOrEqual,
    UnsignedGreaterThan,
    UnsignedGreaterThanOrEqual,
}

/// Floating-point comparison condition (Cranelift-style).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FloatCC {
    Ordered,
    Unordered,
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
}

/// A function signature: scalar parameters and an optional scalar result.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Signature {
    pub params: Vec<Type>,
    pub ret: Option<Type>,
}

impl Signature {
    pub fn new(params: impl Into<Vec<Type>>, ret: Option<Type>) -> Signature {
        Signature {
            params: params.into(),
            ret,
        }
    }
}

pub(crate) fn icmp_op(ty: Type, cc: IntCC) -> &'static str {
    match (ty, cc) {
        (Type::I64, IntCC::Equal) => "ceql",
        (Type::I64, IntCC::NotEqual) => "cnel",
        (Type::I64, IntCC::SignedLessThan) => "csltl",
        (Type::I64, IntCC::SignedLessThanOrEqual) => "cslel",
        (Type::I64, IntCC::SignedGreaterThan) => "csgtl",
        (Type::I64, IntCC::SignedGreaterThanOrEqual) => "csgel",
        (Type::I64, IntCC::UnsignedLessThan) => "cultl",
        (Type::I64, IntCC::UnsignedLessThanOrEqual) => "culel",
        (Type::I64, IntCC::UnsignedGreaterThan) => "cugtl",
        (Type::I64, IntCC::UnsignedGreaterThanOrEqual) => "cugel",
        (_, IntCC::Equal) => "ceqw",
        (_, IntCC::NotEqual) => "cnew",
        (_, IntCC::SignedLessThan) => "csltw",
        (_, IntCC::SignedLessThanOrEqual) => "cslew",
        (_, IntCC::SignedGreaterThan) => "csgtw",
        (_, IntCC::SignedGreaterThanOrEqual) => "csgew",
        (_, IntCC::UnsignedLessThan) => "cultw",
        (_, IntCC::UnsignedLessThanOrEqual) => "culew",
        (_, IntCC::UnsignedGreaterThan) => "cugtw",
        (_, IntCC::UnsignedGreaterThanOrEqual) => "cugew",
    }
}

pub(crate) fn fcmp_op(ty: Type, cc: FloatCC) -> &'static str {
    let single = ty == Type::F32;
    match cc {
        FloatCC::Ordered => {
            if single {
                "cos"
            } else {
                "cod"
            }
        }
        FloatCC::Unordered => {
            if single {
                "cuos"
            } else {
                "cuod"
            }
        }
        FloatCC::Equal => {
            if single {
                "ceqs"
            } else {
                "ceqd"
            }
        }
        FloatCC::NotEqual => {
            if single {
                "cnes"
            } else {
                "cned"
            }
        }
        FloatCC::LessThan => {
            if single {
                "clts"
            } else {
                "cltd"
            }
        }
        FloatCC::LessThanOrEqual => {
            if single {
                "cles"
            } else {
                "cled"
            }
        }
        FloatCC::GreaterThan => {
            if single {
                "cgts"
            } else {
                "cgtd"
            }
        }
        FloatCC::GreaterThanOrEqual => {
            if single {
                "cges"
            } else {
                "cged"
            }
        }
    }
}
