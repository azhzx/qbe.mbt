#include <stdio.h>

extern int add(int a, int b);
extern int fib(int n);

int main(void) {
  int a = add(20, 22);
  int f = fib(10);
  printf("add(20,22)=%d fib(10)=%d\n", a, f);
  return (a == 42 && f == 55) ? 0 : 1;
}