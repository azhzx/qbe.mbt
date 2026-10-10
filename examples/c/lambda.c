#include <stdio.h>
#include <lambda.h>

int main()
{

    auto a = 100;
    auto b = 20;

    auto f = lambda (a, &b) int (int x, int y) {
        return a + (*b) + x + y;
    };

    printf("%d\n", f(1, 2));

    return 0;
}