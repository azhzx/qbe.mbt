#include <stdio.h>

#define MakeResult(T, E) \
    typedef  { \
        T value; \
        E error; \
    } Result_##T##_##E;

int main() {

}