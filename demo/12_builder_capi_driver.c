/*
 * Driver for demo/12_builder_capi.c: links against the objects the builder
 * program emitted and calls the functions they define.
 */
#include <stdio.h>

extern int tri(int n);
extern int add(int a, int b);

int main(void) {
  int t = tri(10);
  int a = add(20, 22);
  printf("tri(10)=%d add(20,22)=%d\n", t, a);
  return (t == 55 && a == 42) ? 0 : 1;
}