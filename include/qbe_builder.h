#ifndef QBE_BUILDER_H
#define QBE_BUILDER_H

/*
 * C ABI for the programmatic QBE IL builder (azhzx/qbe).
 *
 * A program builds one module with a `qbe_builder_t` handle, then calls
 * `qbe_emit_asm` (text) or `qbe_emit_object` (a self-contained Mach-O arm64
 * object). The object has no dependency on the MoonBit runtime and can be
 * linked straight into a C program.
 *
 * Handles are plain integers. `qbe_value_t` is -1 for "none".
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

/* IR class codes. */
#define QBE_W 0
#define QBE_L 1
#define QBE_S 2
#define QBE_D 3
#define QBE_VOID (-1)

typedef int64_t qbe_builder_t;
typedef int64_t qbe_jit_t;
typedef int32_t qbe_func_t;
typedef int32_t qbe_block_t;
typedef int32_t qbe_value_t;

/* Wrap raw bytes / a C string as a MoonBit `Bytes` value. */
static inline moonbit_bytes_t qbe_bytes(const void *data, size_t len) {
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)len, 0);
  if (len) memcpy(b, data, len);
  return b;
}
static inline moonbit_bytes_t qbe_cstr(const char *s) {
  return qbe_bytes(s, strlen(s));
}
/* Pack `n` int32 class codes for `qbe_add_func`. */
static inline moonbit_bytes_t qbe_params(const int32_t *p, int32_t n) {
  return qbe_bytes(p, (size_t)n * 4);
}
/* Length in bytes of a `Bytes` returned by this API. */
#define qbe_bytes_len(b) ((size_t)Moonbit_array_length(b))

qbe_builder_t qbe_builder_new(void);
void qbe_builder_free(qbe_builder_t b);
/* UTF-8 message for the most recent failure (empty when none). */
moonbit_bytes_t qbe_last_error(void);

qbe_func_t qbe_add_func(qbe_builder_t b, moonbit_bytes_t name, int32_t ret_cls,
                        int32_t is_export, moonbit_bytes_t params);
qbe_value_t qbe_func_param(qbe_builder_t b, qbe_func_t f, int32_t i);
qbe_block_t qbe_entry_block(qbe_builder_t b, qbe_func_t f);
qbe_block_t qbe_add_block(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t label);
void qbe_switch_to(qbe_builder_t b, qbe_func_t f, qbe_block_t blk);
qbe_value_t qbe_block_param(qbe_builder_t b, qbe_func_t f, qbe_block_t blk,
                            int32_t cls);

qbe_value_t qbe_const_int(qbe_builder_t b, qbe_func_t f, int64_t v);
qbe_value_t qbe_const_double(qbe_builder_t b, qbe_func_t f, double v);
qbe_value_t qbe_const_single(qbe_builder_t b, qbe_func_t f, float v);
qbe_value_t qbe_global(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t name);

/* to =<cls> <op> a1, a2. `res_cls` = QBE_VOID for a void instruction. */
qbe_value_t qbe_emit(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t op,
                     int32_t cls, int32_t res_cls, qbe_value_t a1,
                     qbe_value_t a2);
void qbe_emit_void(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t op,
                   int32_t cls, qbe_value_t a1, qbe_value_t a2);
/* Emit one call argument; call once per argument, then `qbe_call`. */
void qbe_arg(qbe_builder_t b, qbe_func_t f, int32_t cls, qbe_value_t val);
qbe_value_t qbe_call(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t callee,
                     int32_t ret_cls);

void qbe_ret(qbe_builder_t b, qbe_func_t f, qbe_value_t val);
void qbe_jmp(qbe_builder_t b, qbe_func_t f, qbe_block_t dest);
void qbe_jmp1(qbe_builder_t b, qbe_func_t f, qbe_block_t dest, qbe_value_t a0);
void qbe_jmp2(qbe_builder_t b, qbe_func_t f, qbe_block_t dest, qbe_value_t a0,
              qbe_value_t a1);
void qbe_jmp3(qbe_builder_t b, qbe_func_t f, qbe_block_t dest, qbe_value_t a0,
              qbe_value_t a1, qbe_value_t a2);
void qbe_jmp4(qbe_builder_t b, qbe_func_t f, qbe_block_t dest, qbe_value_t a0,
              qbe_value_t a1, qbe_value_t a2, qbe_value_t a3);
void qbe_jnz(qbe_builder_t b, qbe_func_t f, qbe_value_t cond, qbe_block_t then_blk,
             qbe_block_t else_blk);
void qbe_jnz1(qbe_builder_t b, qbe_func_t f, qbe_value_t cond,
              qbe_block_t then_blk, qbe_value_t then_arg, qbe_block_t else_blk,
              qbe_value_t else_arg);
/* Variable-arity branches: args are little-endian int32 value arrays. */
void qbe_jmp_n(qbe_builder_t b, qbe_func_t f, qbe_block_t dest,
               moonbit_bytes_t args);
void qbe_jnz_n(qbe_builder_t b, qbe_func_t f, qbe_value_t cond,
               qbe_block_t then_blk, moonbit_bytes_t then_args,
               qbe_block_t else_blk, moonbit_bytes_t else_args);

void qbe_data_string(qbe_builder_t b, moonbit_bytes_t name, int32_t is_export,
                     moonbit_bytes_t s);
void qbe_data_bytes(qbe_builder_t b, moonbit_bytes_t name, int32_t is_export,
                    moonbit_bytes_t data);

/* QBE IL text for the constructed module (UTF-8, re-parseable). */
moonbit_bytes_t qbe_emit_il(qbe_builder_t b);
/* In-memory JIT: compile the module, map it executable and return a handle
 * (0 on failure; see qbe_last_error). Resolve symbols with qbe_jit_symbol /
 * qbe_jit_global and release the mapping with qbe_jit_free. */
qbe_jit_t qbe_jit_load(qbe_builder_t b);
/* Register a host callback symbol, consulted before dlsym at load time. */
void qbe_jit_symbol_define(moonbit_bytes_t name, int64_t addr);
void qbe_jit_symbol_clear(void);
int64_t qbe_jit_symbol(qbe_jit_t jit, moonbit_bytes_t name);
int64_t qbe_jit_global(qbe_jit_t jit, moonbit_bytes_t name);
void qbe_jit_free(qbe_jit_t jit);

/* UTF-8 arm64 assembly text. */
moonbit_bytes_t qbe_emit_asm(qbe_builder_t b);
/* Self-contained Mach-O arm64 object. */
moonbit_bytes_t qbe_emit_object(qbe_builder_t b);

/* UTF-8 arm64 assembly text for a gas flavor ("e" ELF, "m" Mach-O). */
moonbit_bytes_t qbe_emit_asm_gas(qbe_builder_t b, moonbit_bytes_t gas);
/* Enable (1) or disable (0) DWARF debug info in qbe_emit_asm output. */
void qbe_dbg_enable(int32_t on);
/* Set the compilation-unit name and directory. */
void qbe_dbg_compile_unit(qbe_builder_t b, moonbit_bytes_t name,
                          moonbit_bytes_t dir);
/*
 * Declare a debug variable bound to value `val` in function `f`.
 * `ty` is 0=w, 1=l, 2=s, 3=d, 4=pointer, 5=aggregate (named by `type_name`,
 * sized by `size`).
 */
void qbe_dbg_var(qbe_builder_t b, qbe_func_t f, moonbit_bytes_t name,
                 int32_t ty, moonbit_bytes_t type_name, int32_t size,
                 qbe_value_t val);
/* Attach a source location (line, column) at the current point. */
void qbe_dbg_loc(qbe_builder_t b, qbe_func_t f, int32_t line, int32_t col);
#ifdef __cplusplus
}
#endif

#endif /* QBE_BUILDER_H */