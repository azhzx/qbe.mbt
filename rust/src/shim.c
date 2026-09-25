/* C shim for the Rust glue layer.
 *
 * The qbe_* ABI exchanges strings and blobs as MoonBit `Bytes` values, whose
 * length lives in the MoonBit object header. Rust must not know that layout,
 * so this file exposes plain (ptr, len) helpers and a one-shot runtime
 * initializer. It is compiled by build.rs and linked into the crate archive. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "moonbit.h"
#include "qbe_builder.h"

extern void moonbit_runtime_init(int argc, char **argv);
extern void moonbit_init(void);

/* Initialize the MoonBit runtime and this module. Call once per process,
 * before any qbe_* call. */
void qbe_glue_init(void) {
  moonbit_runtime_init(0, NULL);
  moonbit_init();
}

/* Wrap a raw byte buffer as a MoonBit Bytes value (owned by the caller). */
moonbit_bytes_t qbe_glue_bytes(const uint8_t *ptr, size_t len) {
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0 && ptr != NULL) {
    memcpy(b, ptr, len);
  }
  return b;
}

size_t qbe_glue_len(moonbit_bytes_t b) {
  return b == NULL ? 0 : (size_t)Moonbit_array_length(b);
}

void qbe_glue_free(moonbit_bytes_t b) {
  if (b != NULL) {
    moonbit_decref(b);
  }
}

/* Copy the last error message into out (UTF-8) and return its full length. */
size_t qbe_glue_error_copy(uint8_t *out, size_t cap) {
  moonbit_bytes_t e = qbe_last_error();
  size_t n = qbe_glue_len(e);
  size_t m = n < cap ? n : cap;
  if (m > 0 && out != NULL) {
    memcpy(out, e, m);
  }
  qbe_glue_free(e);
  return n;
}