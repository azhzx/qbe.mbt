#include <stdio.h>

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void) {
  for (int i = 0; i < 10; i++) {
    printf("fib(%d) = %d\n", i, fib(i));
  }
  return 0;
}
