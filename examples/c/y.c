#include <stdio.h>
#include <lambda.h>

/*
 * Recursion through a closure, in the spirit of the Y combinator.
 *
 * The C++ version
 *
 *     auto Y = [](auto f) {
 *         return [f](auto x) {
 *             return f([f](auto y) { return f(f)(y); })(x);
 *         };
 *     };
 *
 * leans on generic lambdas: every instantiation of `f` is a distinct type,
 * which is what lets `f` be applied to itself. qpcc closures have fixed
 * types, so `f(f)` has no type to write - self application needs a type that
 * mentions itself. What is expressible is the same idea with the cycle closed
 * through the environment instead: capture a pointer to the closure and read it
 * back afterwards.
 */

typedef lambda int (int) IntFn; /* int -> int */

int main(void) {
  IntFn self = { 0, 0 }; /* filled in once the closure exists */

  /* fact captures a pointer to `self`, so the body can call whatever `self`
     holds by the time it runs. */
  auto fact = lambda (&self) int (int n) {
    return n <= 1 ? 1 : n * (*self)(n - 1);
  };
  self = fact; /* close the loop */

  printf("fact(5) = %d\n", fact(5));
  printf("fact(10) = %d\n", fact(10));

  /* A second recursive closure over the same shape: Fibonacci. */
  IntFn fib_self = { 0, 0 };
  auto fib = lambda (&fib_self) int (int n) {
    return n < 2 ? n : (*fib_self)(n - 1) + (*fib_self)(n - 2);
  };
  fib_self = fib;

  printf("fib(10) = %d\n", fib(10));
  return fact(5) == 120 && fib(10) == 55 ? 0 : 1;
}
