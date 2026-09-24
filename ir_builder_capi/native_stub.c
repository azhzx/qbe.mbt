/*
 * A `foreign_library` package is not an executable, but `moon build` still
 * links an executable shim for it. The useful artifact is the object file
 * (which carries the `qbe_*` exports); this no-op entry point just satisfies
 * the linker.
 */
int main(void) { return 0; }