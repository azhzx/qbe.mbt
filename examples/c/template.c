#include <stdio.h>
#include <taggedunion.h>

#define MakeResult(T, E) \
    typedef tagunion { \
        T ok; \
        E err; \
    } Result_([T, E]);


MakeResult(int, const char*);

int main() {
    auto r1 = Result_([int, const char*]) { 
        .ok = 42
     };
    auto r2 = Result_([int, const char*]) { 
        .err = "An error occurred" 
    };

    printf("Result 1: %d\n", r1.ok);
    printf("Result 2: %s\n", r2.err);
    return 0;
}
