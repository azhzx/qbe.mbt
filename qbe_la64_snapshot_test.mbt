// End-to-end snapshot tests for the LoongArch64 (la64, LP64D) backend.
//
// The reference C QBE (tools/qbe-ref) has no loongarch64 target, so these
// snapshots are generated with `moon test --update` and verified by hand
// against the LoongArch64 ELF psABI and the GNU assembler syntax. Do not
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl one
          #|	.type one, @function
          #|one:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	li.d $a0, 1
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size one, .-one
          #|/* end function one */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl arith
          #|	.type arith, @function
          #|arith:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	add.w $t0, $a0, $a1
          #|	li.d $t1, 3
          #|	mul.w $a0, $t0, $t1
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size arith, .-arith
          #|/* end function arith */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl rec
          #|	.type rec, @function
          #|rec:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	li.d $t0, 0
          #|	li.d $t1, 1
          #|	slt $t0, $t0, $a0
          #|	xor $t0, $t0, $t1
          #|	beqz $t0, .L2
          #|.L1:
          #|	li.d $a0, 0
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|.L2:
          #|	li.d $t0, 1
          #|	sub.w $a0, $a0, $t0
          #|	bl rec
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size rec, .-rec
          #|/* end function rec */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl sum
          #|	.type sum, @function
          #|sum:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	b .L3
          #|.L1:
          #|	or $t2, $t1, $zero
          #|	or $t1, $t0, $zero
          #|	li.d $t0, 1
          #|	add.w $t0, $t1, $t0
          #|	add.w $t1, $t2, $t1
          #|	slt $t2, $t0, $a0
          #|	beqz $t2, .L4
          #|	b .L1
          #|.L2:
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|.L4:
          #|	or $a0, $t1, $zero
          #|	b .L2
          #|.L3:
          #|	li.d $t1, 0
          #|	li.d $t0, 0
          #|	b .L1
          #|	.size sum, .-sum
          #|/* end function sum */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl mem
          #|	.type mem, @function
          #|mem:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size mem, .-mem
          #|/* end function mem */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl dmul
          #|	.type dmul, @function
          #|dmul:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	fmul.d $fa0, $fa0, $fa1
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size dmul, .-dmul
          #|/* end function dmul */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
    Ok(assembly) =>
      inspect(
        assembly,
        content=(
          #|	.globl dadd
          #|	.type dadd, @function
          #|dadd:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	la.local $t8, fp0
          #|	fld.d $ft0, $t8, 0
          #|	fadd.d $fa0, $fa0, $ft0
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size dadd, .-dadd
          #|/* end function dadd */
          #|
          #|/* floating point constants */
          #|.data
          #|.balign 8
          #|.Lfp0:
          #|	.word 0
          #|	.word 1074003968 /* 2.500000 */
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
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
  match @qbe.compile_la64(src) {
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
          #|	.globl first
          #|	.type first, @function
          #|first:
          #|	st.d $fp, $sp, -16
          #|	st.d $ra, $sp, -8
          #|	addi.d $fp, $sp, -16
          #|	addi.d $sp, $sp, -16
          #|	la.local $t8, buf
          #|	ld.bu $a0, $t8, 0
          #|	addi.d $sp, $fp, 16
          #|	ld.d $ra, $fp, 8
          #|	ld.d $fp, $fp, 0
          #|	ret
          #|	.size first, .-first
          #|/* end function first */
          #|
          #|
        ),
      )
    Err(_) => fail("compile_la64 failed")
  }
}
