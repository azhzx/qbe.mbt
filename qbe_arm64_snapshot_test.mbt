// End-to-end snapshot tests for the ARM64 (AArch64, AAPCS64 ELF) backend.
//
// The byte-level reference is `vendor/qbe/qbe -t arm64`; these
// snapshots are generated with `moon test --update` from outputs that already
// match the reference assembly byte-for-byte (see `python compare.py
// --target arm64 --asm`). Do not edit the `content=` snapshots casually:
// every change must be justified by an intentional backend change.

///|
test "e2e arm64: return constant word" {
  let src =
    #|export
    #|function w $one() {
    #|@start
    #|    ret 1
    #|
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl one
          #|one:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	mov	w0, #1
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type one, @function
          #|.size one, .-one
          #|/* end function one */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: word arithmetic" {
  let src =
    #|export
    #|function w $arith(w %a, w %b) {
    #|@start
    #|    %s =w add %a, %b
    #|    %p =w mul %s, 3
    #|    ret %p
    #|
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl arith
          #|arith:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	add	w0, w0, w1
          #|	mov	w1, #3
          #|	mul	w0, w0, w1
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type arith, @function
          #|.size arith, .-arith
          #|/* end function arith */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: call and branch" {
  let src =
    #|export
    #|function w $callee(w %x) {
    #|@start
    #|    ret %x
    #|}
    #|export
    #|function w $caller(w %a) {
    #|@start
    #|    %c =w csgtw %a, 0
    #|    jnz %c, @pos, @neg
    #|@pos
    #|    %r =w call $callee(w %a)
    #|    ret %r
    #|@neg
    #|    ret 0
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl callee
          #|callee:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type callee, @function
          #|.size callee, .-callee
          #|/* end function callee */
          #|
          #|.text
          #|.balign 16
          #|.globl caller
          #|caller:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	cmp	w0, #0
          #|	bgt	.L3
          #|	mov	w0, #0
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.L3:
          #|	bl	callee
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type caller, @function
          #|.size caller, .-caller
          #|/* end function caller */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: loop with phi" {
  let src =
    #|export
    #|function w $count(w %n) {
    #|@start
    #|    jnz %n, @loop, @done
    #|@loop
    #|    %n2 =w phi @start %n, @loop %m
    #|    %m =w sub %n2, 1
    #|    %c =w csgtw %m, 0
    #|    jnz %c, @loop, @done
    #|@done
    #|    ret 0
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl count
          #|count:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	cmp	w0, #0
          #|	beq	.L2
          #|.L1:
          #|	mov	w1, #1
          #|	sub	w0, w0, w1
          #|	cmp	w0, #0
          #|	bgt	.L1
          #|.L2:
          #|	mov	w0, #0
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type count, @function
          #|.size count, .-count
          #|/* end function count */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: memory and alloc" {
  let src =
    #|export
    #|function w $mem() {
    #|@start
    #|    %p =l alloc4 4
    #|    storew 7, %p
    #|    %v =w loadw %p
    #|    ret %v
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl mem
          #|mem:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	mov	w0, #7
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type mem, @function
          #|.size mem, .-mem
          #|/* end function mem */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: double arithmetic" {
  let src =
    #|export
    #|function d $dadd(d %a, d %b) {
    #|@start
    #|    %s =d add %a, %b
    #|    ret %s
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl dadd
          #|dadd:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	fadd	d0, d0, d1
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type dadd, @function
          #|.size dadd, .-dadd
          #|/* end function dadd */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: float constant stash" {
  let src =
    #|export
    #|function d $fconst() {
    #|@start
    #|    ret d_1.5
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.text
          #|.balign 16
          #|.globl fconst
          #|fconst:
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	adrp	x0, ".Lfp0"
          #|	add	x0, x0, #:lo12:".Lfp0"
          #|	ldr	d0, [x0]
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type fconst, @function
          #|.size fconst, .-fconst
          #|/* end function fconst */
          #|
          #|/* floating point constants */
          #|.section .rodata
          #|.p2align 3
          #|.Lfp0:
          #|	.quad 4609434218613702656 /* 1.500000 */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|



        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}

///|
test "e2e arm64: data section" {
  let src =
    #|data $buf = { b 1, b 2, b 3, z 1 }
    #|export
    #|function w $first() {
    #|@start
    #|    %r =w loadub $buf
    #|    ret %r
    #|}
  match @qbe.compile_arm64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|.data
          #|.align 8
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
          #|	hint	#34
          #|	stp	x29, x30, [sp, -16]!
          #|	mov	x29, sp
          #|	adrp	x0, buf
          #|	add	x0, x0, #:lo12:buf
          #|	ldrb	w0, [x0]
          #|	ldp	x29, x30, [sp], 16
          #|	ret
          #|.type first, @function
          #|.size first, .-first
          #|/* end function first */
          #|
          #|.section .note.GNU-stack,"",@progbits
          #|


        ),
      )
    Err(_) => fail("compile_arm64 failed")
  }
}
