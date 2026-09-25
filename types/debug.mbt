///|
// A debug-info type for a programmatically declared variable. QBE IL has no
// type system beyond word/long/single/double and opaque `:type` aggregates, so
// the builder's front end supplies these (the same split Cranelift uses: it
// exposes value labels and lets the embedder describe the language types).
pub(all) enum DbgType {
  DbgW // 32-bit integer
  DbgL // 64-bit integer
  DbgS // single-precision float
  DbgD // double-precision float
  DbgPtr // pointer (void*)
  DbgAgg(String, Int) // aggregate: name, byte size
} derive(Eq, Debug)

///|
// A variable declared by the builder (or the C ABI): the name and type come
// from the front end; the value is an IR temp whose final register or stack
// slot is resolved after register allocation.
pub(all) struct DbgVar {
  name : String
  ty : DbgType
  tmp : Int // tmp id holding the value
} derive(Debug)
