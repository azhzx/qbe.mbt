/*
 * demo/12_builder_capi.c - build QBE IL from C.
 *
 * Instead of writing .ssa text, this program constructs the IL through the
 * programmatic builder C ABI (include/qbe_builder.h):
 *
 *   export function w $add(w %a, w %b) { @start  %r =w add %a, %b  ret %r }
 *
 *   export function w $tri(w %n) {          // 1 + 2 + ... + n
 *   @start
 *     %c0 =w csgtw %n, 0
 *     jnz %c0, @init, @zero
 *   @init
 *     jmp @loop(1, 0)                       // block parameters
 *   @zero
 *     ret 0
 *   @loop
 *     %i  =w phi @init 1, @body %i2
 *     %s  =w phi @init 0, @body %s2
 *     %s2 =w add %s, %i
 *     %i2 =w add %i, 1
 *     %c  =w cslew %i2, %n
 *     jnz %c, @body, @end
 *   @body
 *     jmp @loop(%i2, %s2)
 *   @end
 *     ret %s2
 *   }
 *
 * It then prints the generated arm64 assembly and writes self-contained
 * Mach-O objects (12_tri.o, 12_add.o) into OUTDIR.
 *
 * Usage: 12_builder_capi [OUTDIR]
 *
 * See scripts/run_builder_demo.sh for the full build/link/run recipe.
 */
#include <stdio.h>
#include <stdlib.h>
#include "qbe_builder.h"
#include "moonbit_runtime.h"

/* Provided by the MoonBit runtime; call them once before any qbe_* call. */
extern void moonbit_runtime_init(int argc, char **argv);
extern void moonbit_init(void);

static void die(const char *what) {
  moonbit_bytes_t e = qbe_last_error();
  fprintf(stderr, "qbe: %s failed: %.*s\n", what, (int)qbe_bytes_len(e),
          (const char *)e);
  exit(1);
}

/* export function w $add(w %a, w %b) */
static qbe_builder_t make_add(void) {
  qbe_builder_t b = qbe_builder_new();
  int32_t ps[2] = { QBE_W, QBE_W };
  qbe_func_t f = qbe_add_func(b, qbe_cstr("add"), QBE_W, 1, qbe_params(ps, 2));
  qbe_value_t a = qbe_func_param(b, f, 0);
  qbe_value_t c = qbe_func_param(b, f, 1);
  qbe_value_t r = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, a, c);
  qbe_ret(b, f, r);
  return b;
}

/* export function w $tri(w %n): 1 + 2 + ... + n, with a phi loop. */
static qbe_builder_t make_tri(void) {
  qbe_builder_t b = qbe_builder_new();
  int32_t ps[1] = { QBE_W };
  qbe_func_t f = qbe_add_func(b, qbe_cstr("tri"), QBE_W, 1, qbe_params(ps, 1));
  qbe_value_t n = qbe_func_param(b, f, 0);
  qbe_block_t init = qbe_add_block(b, f, qbe_cstr("init"));
  qbe_block_t zero = qbe_add_block(b, f, qbe_cstr("zero"));
  qbe_block_t loop = qbe_add_block(b, f, qbe_cstr("loop"));
  qbe_block_t body = qbe_add_block(b, f, qbe_cstr("body"));
  qbe_block_t end = qbe_add_block(b, f, qbe_cstr("end"));
  qbe_value_t one = qbe_const_int(b, f, 1);
  qbe_value_t z = qbe_const_int(b, f, 0);

  /* @start: if n > 0 goto init else zero */
  qbe_value_t c0 = qbe_emit(b, f, qbe_cstr("csgtw"), QBE_W, QBE_W, n, z);
  qbe_jnz(b, f, c0, init, zero);

  /* @init: jump into the loop with the initial (i, s) = (1, 0) */
  qbe_switch_to(b, f, init);
  qbe_jmp2(b, f, loop, one, z);

  /* @zero: ret 0 */
  qbe_switch_to(b, f, zero);
  qbe_ret(b, f, z);

  /* @loop: %i and %s are block parameters (phi nodes) */
  qbe_switch_to(b, f, loop);
  qbe_value_t i = qbe_block_param(b, f, loop, QBE_W);
  qbe_value_t s = qbe_block_param(b, f, loop, QBE_W);
  qbe_value_t s2 = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, s, i);
  qbe_value_t i2 = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, i, one);
  qbe_value_t c = qbe_emit(b, f, qbe_cstr("cslew"), QBE_W, QBE_W, i2, n);
  qbe_jnz(b, f, c, body, end);

  /* @body: feed the next (i, s) back into the loop */
  qbe_switch_to(b, f, body);
  qbe_jmp2(b, f, loop, i2, s2);

  /* @end: ret %s2 */
  qbe_switch_to(b, f, end);
  qbe_ret(b, f, s2);
  return b;
}

static void print_il(qbe_builder_t b, const char *label) {
  moonbit_bytes_t text = qbe_emit_il(b);
  if (qbe_bytes_len(text) == 0) {
    die("qbe_emit_il");
  }
  printf("/* QBE IL: %s */\n", label);
  fwrite(text, 1, qbe_bytes_len(text), stdout);
  printf("\n");
}

static void print_asm(qbe_builder_t b, const char *label) {
  moonbit_bytes_t text = qbe_emit_asm(b);
  if (qbe_bytes_len(text) == 0) {
    die("qbe_emit_asm");
  }
  printf("/* %s */\n", label);
  fwrite(text, 1, qbe_bytes_len(text), stdout);
  printf("\n");
}

static void write_object(const char *dir, const char *name, qbe_builder_t b) {
  moonbit_bytes_t obj = qbe_emit_object(b);
  if (qbe_bytes_len(obj) == 0) {
    die("qbe_emit_object");
  }
  char path[512];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE *fo = fopen(path, "wb");
  if (fo == NULL) {
    perror(path);
    exit(1);
  }
  if (fwrite(obj, 1, qbe_bytes_len(obj), fo) != qbe_bytes_len(obj)) {
    fclose(fo);
    fprintf(stderr, "qbe: short write to %s\n", path);
    exit(1);
  }
  fclose(fo);
  fprintf(stderr, "wrote %s (%zu bytes)\n", path, qbe_bytes_len(obj));
}

int main(int argc, char **argv) {
  moonbit_runtime_init(argc, argv);
  moonbit_init();
  const char *dir = argc > 1 ? argv[1] : ".";

  /* Serialize the constructed IR back to QBE IL text. */
  print_il(make_tri(), "$tri");
  print_il(make_add(), "$add");

  /* And compile it to arm64 assembly. */
  print_asm(make_tri(), "$tri");
  print_asm(make_add(), "$add");

  write_object(dir, "12_tri.o", make_tri());
  write_object(dir, "12_add.o", make_add());
  return 0;
}