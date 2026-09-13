// End-to-end snapshot tests for the RISC-V 64 (rv64) backend.
//
// The reference C QBE (tools/qbe-ref) has no rv64 target, so these
// snapshots are generated with `moon test --update` and verified by hand
// against the RISC-V lp64d psABI and the GNU assembler syntax.
// edit the `content=` snapshots casually: every change must be justified by
// an intentional backend change.

///|
test "e2e la64: return constant word" {
  let src =
    #|export
    #|function w $one() {
    #|@start
    #|    ret 1
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl one
          #|	.type one, @function
          #|one:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	li a0, 1
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size one, .-one
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: word arithmetic" {
  let src =
    #|export
    #|function w $arith(w %a, w %b) {
    #|@start
    #|    %s =w add %a, %b
    #|    %p =w mul %s, 3
    #|    ret %p
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl arith
          #|	.type arith, @function
          #|arith:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	addw t0, a0, a1
          #|	li t1, 3
          #|	mulw a0, t0, t1
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size arith, .-arith
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: call and branch" {
  let src =
    #|export
    #|function w $rec(w %n) {
    #|@start
    #| %x =w cslew %n, 0
    #| jnz %x, @small, @big
    #|
    #|@small
    #| ret 0
    #|
    #|@big
    #| %m =w sub %n, 1
    #| %r =w call $rec(w %m)
    #| ret %r
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl rec
          #|	.type rec, @function
          #|rec:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	li t0, 0
          #|	li t1, 1
          #|	slt t0, t0, a0
          #|	xor t0, t0, t1
          #|	beqz t0, .L2
          #|.L1:
          #|	li a0, 0
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.L2:
          #|	li t0, 1
          #|	subw a0, a0, t0
          #|	call rec
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size rec, .-rec
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: loop with phi" {
  let src =
    #|export
    #|function w $sum(w %n) {
    #|@start
    #|@loop
    #|    %i =w phi @start 0, @loop %j
    #|    %acc =w phi @start 0, @loop %s
    #|    %j =w add %i, 1
    #|    %s =w add %acc, %i
    #|    %c =w csltw %j, %n
    #|    jnz %c, @loop, @done
    #|
    #|@done
    #|    ret %s
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl sum
          #|	.type sum, @function
          #|sum:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	j .L3
          #|.L1:
          #|	mv t3, t2
          #|	mv t2, t1
          #|	li t1, 1
          #|	addw t1, t2, t1
          #|	addw t2, t3, t2
          #|	slt t3, t1, a0
          #|	beqz t3, .L4
          #|	j .L1
          #|.L2:
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.L4:
          #|	mv a0, t2
          #|	j .L2
          #|.L3:
          #|	li t2, 0
          #|	li t1, 0
          #|	j .L1
          #|	.size sum, .-sum
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: memory and alloc" {
  let src =
    #|export
    #|function w $mem(w %v) {
    #|@start
    #|    %p =l alloc4 8
    #|    storew %v, %p
    #|    %r =w loadsw %p
    #|    ret %r
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl mem
          #|	.type mem, @function
          #|mem:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size mem, .-mem
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: double arithmetic" {
  let src =
    #|export
    #|function d $dmul(d %a, d %b) {
    #|@start
    #|    %r =d mul %a, %b
    #|    ret %r
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl dmul
          #|	.type dmul, @function
          #|dmul:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	fmul.d fa0, fa0, fa1
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size dmul, .-dmul
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: float constant stash" {
  let src =
    #|export
    #|function d $dadd(d %a) {
    #|@start
    #|    %r =d add %a, d_2.5
    #|    ret %r
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl dadd
          #|	.type dadd, @function
          #|dadd:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	lla t6, fp0
          #|	fld ft0, 0(t6)
          #|	fadd.d fa0, fa0, ft0
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size dadd, .-dadd
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e la64: data section" {
  let src =
    #|data $buf = { b 1, b 2, b 3, z 1 }
    #|
    #|export function w $first() {
    #|@start
    #|    %r =w loadub $buf
    #|    ret %r
    #|
    #|}
  match @qbe.compile_rv64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl first
          #|	.type first, @function
          #|first:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -32
          #|	sd s1, 0(sp)
          #|	sd s2, 8(sp)
          #|	lla t6, buf
          #|	lbu a0, 0(t6)
          #|	ld s1, 0(sp)
          #|	ld s2, 8(sp)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|	.size first, .-first
          #|
        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}
