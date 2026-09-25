///|
// A self-contained executable code block: machine code copied into
// mmap'd memory and made executable.
pub struct ExecBlock {
  addr : Int64
  size : Int
}

///|
// Copy a route-B module image into writable memory, leaving the code region RW
// so the JIT loader can patch relocations before protecting it.
pub fn ExecBlock::load_module_rw(
  image : Bytes,
  _code_bytes : Int,
) -> ExecBlock raise {
  let n = image.length()
  if n == 0 {
    abort("run-asm: empty module image")
  }
  let addr = @native.mbt_native_alloc(n)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  @native.mbt_native_write_bytes(addr, 0, image)
  { addr, size: n, }
}

///|
// Make the first code_bytes executable (RX); the data that follows stays RW.
pub fn ExecBlock::protect(self : ExecBlock, code_bytes : Int) -> Unit raise {
  if @native.mbt_native_protect(self.addr, code_bytes) != 0 {
    abort("run-asm: mprotect failed")
  }
  @native.mbt_native_icache_flush(self.addr, code_bytes)
}

///|
// Copy a route-B module image into memory: the first code_bytes are made
// executable (RX) while any global data that follows stays writable (RW).
pub fn ExecBlock::load_module(
  image : Bytes,
  code_bytes : Int,
) -> ExecBlock raise {
  let exec = ExecBlock::load_module_rw(image, code_bytes)
  exec.protect(code_bytes)
  exec
}

///|
// Copy arm64 code into executable memory.
pub fn ExecBlock::load_text(text : Bytes) -> ExecBlock raise {
  let n = text.length()
  if n == 0 {
    abort("run-asm: empty code")
  }
  let addr = @native.mbt_native_alloc(n)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  @native.mbt_native_write_bytes(addr, 0, text)
  if @native.mbt_native_protect(addr, n) != 0 {
    abort("run-asm: mprotect failed")
  }
  { addr, size: n, }
}

///|
// Call a one-argument i64 function in this code block.
pub fn ExecBlock::call1(self : ExecBlock, a0 : Int64) -> Int64 raise {
  @native.mbt_native_call_i64_1(self.addr, a0)
}

///|
// Call a one-argument i64 function at a word offset into this code block (the
// offset used by Arm64BinModule::fns).
pub fn ExecBlock::call1_at(
  self : ExecBlock,
  off : Int,
  a0 : Int64,
) -> Int64 raise {
  @native.mbt_native_call_i64_1(self.addr + off.to_int64() * 4L, a0)
}

///|
// The base address of the mapped image.
pub fn ExecBlock::base(self : ExecBlock) -> Int64 {
  self.addr
}

///|
// Unmap the image. Call at most once.
pub fn ExecBlock::close(self : ExecBlock) -> Unit {
  if self.addr != 0L {
    @native.mbt_native_free(self.addr, self.size)
  }
}

///|
// A JIT-loaded module: the code image mapped executable, plus the symbol
// tables needed to resolve functions and globals.
pub struct JitModule {
  exec : ExecBlock
  fns : Array[(String, Int)] // function name -> word offset in the text
  datas : Array[(String, Int)] // global name -> byte offset in the data image
  code_bytes : Int // size of the (page-aligned) code region
}

///|
// Map a linked image into executable memory (Route B, no linker).
pub fn JitModule::from_bin_module(m : @qbe.Arm64BinModule) -> JitModule raise {
  JitModule::from_bin_module_ex(m, @qbe.Arm64BinFixups::empty())
}

///|
// Resolve a JIT symbol: a caller-provided table first (host callbacks), then
// dlsym(RTLD_DEFAULT).
fn jit_resolve(symbols : Array[(String, Int64)], name : String) -> Int64 {
  for p in symbols {
    if p.0 == name {
      return p.1
    }
  }
  @native.mbt_native_sym(@native.cstr(name))
}

///|
// Map a linked image, resolve external symbols, patch the veneers and data
// addresses, then protect the code region. `symbols` overrides dlsym for host
// callbacks.
pub fn JitModule::from_bin_module_ex(
  m : @qbe.Arm64BinModule,
  fx : @qbe.Arm64BinFixups,
  symbols? : Array[(String, Int64)] = [],
) -> JitModule raise {
  let exec = ExecBlock::load_module_rw(m.image(), m.code_bytes)
  let base = exec.base()
  // External calls: each 20-byte veneer materializes the full 64-bit address
  // with movz/movk x16 and jumps with br x16 (so any distance works).
  for v in fx.ext_calls {
    let (vw, sym) = v
    let addr = jit_resolve(symbols, sym)
    if addr == 0L {
      raise @util.QbeError::CompileError("jit: unresolved symbol: " + sym)
    }
    let w = vw * 4
    @native.mbt_native_write_u32(
      base,
      w,
      @object.enc_movz_sf(true, 17, (addr & 0xFFFFL).to_int(), 0).reinterpret_as_uint(),
    )
    @native.mbt_native_write_u32(
      base,
      w + 4,
      @object.enc_movk_sf(true, 17, ((addr >> 16) & 0xFFFFL).to_int(), 1).reinterpret_as_uint(),
    )
    @native.mbt_native_write_u32(
      base,
      w + 8,
      @object.enc_movk_sf(true, 17, ((addr >> 32) & 0xFFFFL).to_int(), 2).reinterpret_as_uint(),
    )
    @native.mbt_native_write_u32(
      base,
      w + 12,
      @object.enc_movk_sf(true, 17, ((addr >> 48) & 0xFFFFL).to_int(), 3).reinterpret_as_uint(),
    )
    @native.mbt_native_write_u32(
      base,
      w + 16,
      @object.enc_br(17).reinterpret_as_uint(),
    )
  }
  // External data addresses: patch adrp/add in place (adrp reaches +/-4GB).
  for a in fx.ext_addrs {
    let (adrp_w, add_w, rd, sym, addend) = a
    let addr = jit_resolve(symbols, sym)
    if addr == 0L {
      raise @util.QbeError::CompileError("jit: unresolved symbol: " + sym)
    }
    let target = addr + addend.to_int64()
    let pc = base + (adrp_w * 4).to_int64()
    let page = (target >> 12) - (pc >> 12)
    if page < -1048576L || page > 1048575L {
      raise @util.QbeError::CompileError(
        "jit: data symbol out of adrp range: " + sym,
      )
    }
    @native.mbt_native_write_u32(
      base,
      adrp_w * 4,
      @object.enc_adrp(rd, page.to_int()).reinterpret_as_uint(),
    )
    @native.mbt_native_write_u32(
      base,
      add_w * 4,
      @object.enc_add_imm(rd, rd, (target & 0xFFF).to_int()).reinterpret_as_uint(),
    )
  }
  exec.protect(m.code_bytes)
  { exec, fns: m.fns, datas: m.datas, code_bytes: m.code_bytes, }
}

///|
// Resolve a function to its entry address.
pub fn JitModule::symbol(self : JitModule, name : String) -> Int64 raise {
  for p in self.fns {
    if p.0 == name {
      return self.exec.base() + (p.1 * 4).to_int64()
    }
  }
  raise @util.QbeError::CompileError("jit: no such function: " + name)
}

///|
// Resolve a global to its address (the data image starts after the code).
pub fn JitModule::global(self : JitModule, name : String) -> Int64 raise {
  for p in self.datas {
    if p.0 == name {
      return self.exec.base() + self.code_bytes.to_int64() + p.1.to_int64()
    }
  }
  raise @util.QbeError::CompileError("jit: no such global: " + name)
}

///|
// Function names in the module.
pub fn JitModule::function_names(self : JitModule) -> Array[String] {
  let names : Array[String] = []
  for p in self.fns {
    names.push(p.0)
  }
  names
}

///|
// Call a one-argument i64 function by name.
pub fn JitModule::call_i64_1(
  self : JitModule,
  name : String,
  a0 : Int64,
) -> Int64 raise {
  @native.mbt_native_call_i64_1(self.symbol(name), a0)
}

///|
// Call an integer-argument, integer-returning function by name (0..8 args).
pub fn JitModule::call_i64(
  self : JitModule,
  name : String,
  args : Array[Int64],
) -> Int64 raise {
  let addr = self.symbol(name)
  match args.length() {
    0 => @native.mbt_native_call_i64_0(addr)
    1 => @native.mbt_native_call_i64_1(addr, args[0])
    2 => @native.mbt_native_call_i64_2(addr, args[0], args[1])
    3 => @native.mbt_native_call_i64_3(addr, args[0], args[1], args[2])
    4 => @native.mbt_native_call_i64_4(addr, args[0], args[1], args[2], args[3])
    5 =>
      @native.mbt_native_call_i64_5(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
      )
    6 =>
      @native.mbt_native_call_i64_6(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
      )
    7 =>
      @native.mbt_native_call_i64_7(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
      )
    8 =>
      @native.mbt_native_call_i64_8(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
      )
    _ =>
      raise @util.QbeError::CompileError(
        "jit: call_i64 supports at most 8 arguments",
      )
  }
}

///|
// Call a double-argument, double-returning function by name (0..8 args).
pub fn JitModule::call_f64(
  self : JitModule,
  name : String,
  args : Array[Double],
) -> Double raise {
  let addr = self.symbol(name)
  match args.length() {
    0 => @native.mbt_native_call_f64_0(addr)
    1 => @native.mbt_native_call_f64_1(addr, args[0])
    2 => @native.mbt_native_call_f64_2(addr, args[0], args[1])
    3 => @native.mbt_native_call_f64_3(addr, args[0], args[1], args[2])
    4 => @native.mbt_native_call_f64_4(addr, args[0], args[1], args[2], args[3])
    5 =>
      @native.mbt_native_call_f64_5(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
      )
    6 =>
      @native.mbt_native_call_f64_6(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
      )
    7 =>
      @native.mbt_native_call_f64_7(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
      )
    8 =>
      @native.mbt_native_call_f64_8(
        addr,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
      )
    _ =>
      raise @util.QbeError::CompileError(
        "jit: call_f64 supports at most 8 arguments",
      )
  }
}

///|
// Unmap the code image.
pub fn JitModule::close(self : JitModule) -> Unit {
  self.exec.close()
}
