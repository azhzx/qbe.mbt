/*
 * Emit `add` and `fib` objects through the C builder ABI.
 *
 * Usage: capi_smoke <output-dir>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "qbe_builder.h"
#include "moonbit_runtime.h"

/* Not declared by the public header; provided by libruntime.a. */
extern void moonbit_runtime_init(int argc, char **argv);
/* Runs this module's global initializers. */
extern void moonbit_init(void);

static int write_file(const char *path, moonbit_bytes_t b) {
  FILE *f = fopen(path, "wb");
  if (!f) {
    perror(path);
    return 1;
  }
  size_t n = qbe_bytes_len(b);
  if (n && fwrite(b, 1, n, f) != n) {
    fclose(f);
    return 1;
  }
  fclose(f);
  return 0;
}

static int emit(const char *dir, const char *name, moonbit_bytes_t obj) {
  char path[512];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  return write_file(path, obj);
}

static int build_add(const char *dir) {
  qbe_builder_t b = qbe_builder_new();
  int32_t ps[2] = { QBE_W, QBE_W };
  qbe_func_t f = qbe_add_func(b, qbe_cstr("add"), QBE_W, 1, qbe_params(ps, 2));
  qbe_value_t a = qbe_func_param(b, f, 0);
  qbe_value_t c = qbe_func_param(b, f, 1);
  qbe_value_t r = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, a, c);
  qbe_ret(b, f, r);
  int rc = emit(dir, "add.o", qbe_emit_object(b));
  qbe_builder_free(b);
  return rc;
}

static int build_fib(const char *dir) {
  qbe_builder_t b = qbe_builder_new();
  int32_t ps[1] = { QBE_W };
  qbe_func_t f = qbe_add_func(b, qbe_cstr("fib"), QBE_W, 1, qbe_params(ps, 1));
  qbe_block_t base = qbe_add_block(b, f, qbe_cstr("base"));
  qbe_block_t rec = qbe_add_block(b, f, qbe_cstr("rec"));
  qbe_value_t n = qbe_func_param(b, f, 0);
  qbe_value_t one = qbe_const_int(b, f, 1);
  qbe_value_t cond = qbe_emit(b, f, qbe_cstr("cslew"), QBE_W, QBE_W, n, one);
  qbe_jnz(b, f, cond, base, rec);
  qbe_switch_to(b, f, base);
  qbe_ret(b, f, n);
  qbe_switch_to(b, f, rec);
  qbe_value_t n1 = qbe_emit(b, f, qbe_cstr("sub"), QBE_W, QBE_W, n, one);
  qbe_arg(b, f, QBE_W, n1);
  qbe_value_t f1 = qbe_call(b, f, qbe_cstr("fib"), QBE_W);
  qbe_value_t two = qbe_const_int(b, f, 2);
  qbe_value_t n2 = qbe_emit(b, f, qbe_cstr("sub"), QBE_W, QBE_W, n, two);
  qbe_arg(b, f, QBE_W, n2);
  qbe_value_t f2 = qbe_call(b, f, qbe_cstr("fib"), QBE_W);
  qbe_value_t r = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, f1, f2);
  qbe_ret(b, f, r);
  int rc = emit(dir, "fib.o", qbe_emit_object(b));
  qbe_builder_free(b);
  return rc;
}

int main(int argc, char **argv) {
  moonbit_runtime_init(argc, argv);
  moonbit_init();
  const char *dir = argc > 1 ? argv[1] : ".";
  if (build_add(dir)) return 1;
  if (build_fib(dir)) return 1;
  printf("capi: wrote add.o and fib.o\n");
  return 0;
}