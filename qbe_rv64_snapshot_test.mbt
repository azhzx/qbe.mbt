// End-to-end snapshot tests for the RISC-V 64 (rv64) backend.
//
// These snapshots are generated with `moon test --update` and checked
// against the vendored reference C QBE (`vendor/qbe/qbe -t rv64`), which
// supports rv64, plus the RISC-V lp64d psABI and GNU assembler syntax.
// edit the `content=` snapshots casually: every change must be justified by
// an intentional backend change.

///|
test "e2e rv64: return constant word" {
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
          #|.text
          #|.balign 16
          #|.globl one
          #|one:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	li a0, 1
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type one, @function
          #|.size one, .-one
          #|/* end function one */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: word arithmetic" {
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
          #|.text
          #|.balign 16
          #|.globl arith
          #|arith:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	addw t0, a0, a1
          #|	li t1, 3
          #|	mulw a0, t0, t1
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type arith, @function
          #|.size arith, .-arith
          #|/* end function arith */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: call and branch" {
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
          #|.text
          #|.balign 16
          #|.globl rec
          #|rec:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	li t0, 0
          #|	slt t0, t0, a0
          #|	xor t0, t0, 1
          #|	bnez t0, .L2
          #|	li t0, 1
          #|	subw a0, a0, t0
          #|	call rec
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.L2:
          #|	li a0, 0
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type rec, @function
          #|.size rec, .-rec
          #|/* end function rec */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|




        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: loop with phi" {
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
          #|.text
          #|.balign 16
          #|.globl sum
          #|sum:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	li t1, 0
          #|	li t0, 0
          #|	mv t2, t1
          #|.L2:
          #|	addw t1, t0, 1
          #|	addw t3, t0, t2
          #|	slt t4, t1, a0
          #|	beqz t4, .L4
          #|	mv t2, t3
          #|	mv t0, t1
          #|	j .L2
          #|.L4:
          #|	addw a0, t0, t2
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type sum, @function
          #|.size sum, .-sum
          #|/* end function sum */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|



        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: memory and alloc" {
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
          #|.text
          #|.balign 16
          #|.globl mem
          #|mem:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type mem, @function
          #|.size mem, .-mem
          #|/* end function mem */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: double arithmetic" {
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
          #|.text
          #|.balign 16
          #|.globl dmul
          #|dmul:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	fmul.d fa0, fa0, fa1
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type dmul, @function
          #|.size dmul, .-dmul
          #|/* end function dmul */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: float constant stash" {
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
          #|.text
          #|.balign 16
          #|.globl dadd
          #|dadd:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	lla t6, .Lfp0
          #|	fld ft0, 0(t6)
          #|	fadd.d fa0, fa0, ft0
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type dadd, @function
          #|.size dadd, .-dadd
          #|/* end function dadd */
          #|
          #|/* floating point constants */
          #|.section .rodata
          #|.p2align 3
          #|.Lfp0:
          #|	.quad 4612811918334230528 /* 2.500000 */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}

///|
test "e2e rv64: data section" {
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
          #|.data
          #|.balign 8
          #|buf:
          #|	.byte 1
          #|	.byte 2
          #|	.byte 3
          #|	.fill 1,1,0
          #|/* end data */
          #|
          #|.text
          #|.balign 16
          #|.globl first
          #|first:
          #|	sd fp, -16(sp)
          #|	sd ra, -8(sp)
          #|	add fp, sp, -16
          #|	add sp, sp, -16
          #|	lla t6, buf
          #|	lbu a0, 0(t6)
          #|	add sp, fp, 16
          #|	ld ra, 8(fp)
          #|	ld fp, 0(fp)
          #|	ret
          #|.type first, @function
          #|.size first, .-first
          #|/* end function first */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|

        ),
      )
    Err(_) => fail("compile_rv64 failed")
  }
}
