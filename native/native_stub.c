/* Native shim shared by the JIT and the toolchain-backed runner. Only the
 * pieces MoonBit cannot express itself: executable memory, temp files,
 * process spawn, dynamic linking, and calling a code address. Addresses
 * cross the FFI as int64_t. */
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <dlfcn.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#endif

/* ---- executable memory ------------------------------------------------ */

/* The feature targets macOS/aarch64: the machine code is aarch64 and the
 * toolchain invocation uses Mach-O (-dynamiclib/.dylib). Elsewhere the
 * platform-specific tests skip. */
MOONBIT_FFI_EXPORT
int32_t mbt_native_host_supported(void) {
#if defined(__APPLE__) && defined(__aarch64__)
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT
int64_t mbt_native_alloc(int32_t size) {
  void *p = mmap(NULL, (size_t)size, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANON, -1, 0);
  if (p == MAP_FAILED) return 0;
  return (int64_t)(uintptr_t)p;
}

MOONBIT_FFI_EXPORT
int32_t mbt_native_protect(int64_t addr, int32_t size) {
  return mprotect((void *)(uintptr_t)addr, (size_t)size,
                  PROT_READ | PROT_EXEC) == 0 ? 0 : -1;
}

MOONBIT_FFI_EXPORT
void mbt_native_free(int64_t addr, int32_t size) {
  if (addr) munmap((void *)(uintptr_t)addr, (size_t)size);
}


/* ---- typed JIT call stubs: N integer or N float arguments ------------- */
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_0(int64_t a) { return ((int64_t (*)(void))a)(); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_2(int64_t a, int64_t a0, int64_t a1) { return ((int64_t (*)(int64_t, int64_t))a)(a0, a1); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_3(int64_t a, int64_t a0, int64_t a1, int64_t a2) { return ((int64_t (*)(int64_t, int64_t, int64_t))a)(a0, a1, a2); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_4(int64_t a, int64_t a0, int64_t a1, int64_t a2, int64_t a3) { return ((int64_t (*)(int64_t, int64_t, int64_t, int64_t))a)(a0, a1, a2, a3); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_5(int64_t a, int64_t a0, int64_t a1, int64_t a2, int64_t a3, int64_t a4) { return ((int64_t (*)(int64_t, int64_t, int64_t, int64_t, int64_t))a)(a0, a1, a2, a3, a4); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_6(int64_t a, int64_t a0, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5) { return ((int64_t (*)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t))a)(a0, a1, a2, a3, a4, a5); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_7(int64_t a, int64_t a0, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) { return ((int64_t (*)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t))a)(a0, a1, a2, a3, a4, a5, a6); }
MOONBIT_FFI_EXPORT int64_t mbt_native_call_i64_8(int64_t a, int64_t a0, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6, int64_t a7) { return ((int64_t (*)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t))a)(a0, a1, a2, a3, a4, a5, a6, a7); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_0(int64_t a) { return ((double (*)())a)(); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_1(int64_t a, double d0) { return ((double (*)(double))a)(d0); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_2(int64_t a, double d0, double d1) { return ((double (*)(double, double))a)(d0, d1); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_3(int64_t a, double d0, double d1, double d2) { return ((double (*)(double, double, double))a)(d0, d1, d2); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_4(int64_t a, double d0, double d1, double d2, double d3) { return ((double (*)(double, double, double, double))a)(d0, d1, d2, d3); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_5(int64_t a, double d0, double d1, double d2, double d3, double d4) { return ((double (*)(double, double, double, double, double))a)(d0, d1, d2, d3, d4); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_6(int64_t a, double d0, double d1, double d2, double d3, double d4, double d5) { return ((double (*)(double, double, double, double, double, double))a)(d0, d1, d2, d3, d4, d5); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_7(int64_t a, double d0, double d1, double d2, double d3, double d4, double d5, double d6) { return ((double (*)(double, double, double, double, double, double, double))a)(d0, d1, d2, d3, d4, d5, d6); }
MOONBIT_FFI_EXPORT double mbt_native_call_f64_8(int64_t a, double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7) { return ((double (*)(double, double, double, double, double, double, double, double))a)(d0, d1, d2, d3, d4, d5, d6, d7); }

/* Flush the instruction cache after writing code (a no-op on x86-64). */
MOONBIT_FFI_EXPORT
void mbt_native_icache_flush(int64_t addr, int32_t size) {
#if defined(__APPLE__)
  sys_icache_invalidate((void *)(uintptr_t)addr, (size_t)size);
#elif defined(__GNUC__)
  __builtin___clear_cache((char *)(uintptr_t)addr,
                          (char *)(uintptr_t)addr + size);
#else
  (void)addr;
  (void)size;
#endif
}

MOONBIT_FFI_EXPORT
void mbt_native_write_bytes(int64_t addr, int32_t off, moonbit_bytes_t data) {
  int32_t len = Moonbit_array_length(data);
  memcpy((uint8_t *)(uintptr_t)addr + off, data, (size_t)len);
}

MOONBIT_FFI_EXPORT
void mbt_native_write_u32(int64_t addr, int32_t off, uint32_t word) {
  memcpy((uint8_t *)(uintptr_t)addr + off, &word, sizeof word);
}

/* ---- temp files ------------------------------------------------------- */

MOONBIT_FFI_EXPORT
moonbit_bytes_t mbt_native_temp(moonbit_bytes_t suffix) {
  char tmpl[256];
  snprintf(tmpl, sizeof tmpl, "/tmp/qbe_run_asm_XXXXXX%s", (const char *)suffix);
  int fd = mkstemps(tmpl, (int)strlen((const char *)suffix));
  if (fd >= 0) close(fd);
  int32_t n = (int32_t)strlen(tmpl);
  moonbit_bytes_t b = moonbit_make_bytes(n, 0);
  memcpy(b, tmpl, (size_t)n);
  return b;
}

MOONBIT_FFI_EXPORT
int32_t mbt_native_write_file(moonbit_bytes_t path, moonbit_bytes_t data) {
  FILE *f = fopen((const char *)path, "wb");
  if (!f) return -1;
  int32_t n = Moonbit_array_length(data);
  if (n > 0 && fwrite(data, 1, (size_t)n, f) != (size_t)n) {
    fclose(f);
    return -1;
  }
  return fclose(f) == 0 ? 0 : -1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t mbt_native_read_file(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "rb");
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) n = 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n > 0 && fread(b, 1, (size_t)n, f) != (size_t)n) {
    fclose(f);
    return moonbit_make_bytes(0, 0);
  }
  fclose(f);
  return b;
}

MOONBIT_FFI_EXPORT
int32_t mbt_native_unlink(moonbit_bytes_t path) {
  return unlink((const char *)path) == 0 ? 0 : -1;
}

/* ---- process spawn ---------------------------------------------------- */

MOONBIT_FFI_EXPORT
moonbit_bytes_t mbt_native_capture(moonbit_bytes_t cmd) {
  FILE *f = popen((const char *)cmd, "r");
  if (!f) return moonbit_make_bytes(0, 0);
  size_t cap = 256, len = 0;
  char *buf = malloc(cap);
  size_t n;
  while ((n = fread(buf + len, 1, cap - len, f)) > 0) {
    len += n;
    if (len == cap) {
      cap *= 2;
      buf = realloc(buf, cap);
    }
  }
  pclose(f);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)len, 0);
  memcpy(b, buf, len);
  free(buf);
  return b;
}

MOONBIT_FFI_EXPORT
int32_t mbt_native_run(moonbit_bytes_t cmd) {
  int rc = system((const char *)cmd);
  return rc;
}

/* ---- dynamic linking -------------------------------------------------- */

MOONBIT_FFI_EXPORT
int64_t mbt_native_dlopen(moonbit_bytes_t path) {
  return (int64_t)(uintptr_t)dlopen((const char *)path, RTLD_NOW | RTLD_LOCAL);
}

MOONBIT_FFI_EXPORT
int64_t mbt_native_dlsym(int64_t handle, moonbit_bytes_t name) {
  return (int64_t)(uintptr_t)dlsym((void *)(uintptr_t)handle,
                                   (const char *)name);
}

MOONBIT_FFI_EXPORT
int64_t mbt_native_sym(moonbit_bytes_t name) {
  return (int64_t)(uintptr_t)dlsym(RTLD_DEFAULT, (const char *)name);
}

/* ---- calling code addresses ------------------------------------------- */

MOONBIT_FFI_EXPORT
int64_t mbt_native_call_i64_1(int64_t addr, int64_t a0) {
  return ((int64_t (*)(int64_t))addr)(a0);
}
