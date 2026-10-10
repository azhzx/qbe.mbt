// std=c23 tagged
#include <stdio.h>

typedef _Tagged_union {
  int as_int;
  float as_float;
} Value;

static int 
tag_of(Value v) { 
  return (int)_Dynamic_tag(v); 
}

int 
main() {
  auto v = (Value){ .as_int = 100 };
  printf("tag %d int %d\n", tag_of(v), v.as_int);

  v = (Value){ .as_float = 1.5f };
  auto is_float = (_Dynamic_tag(v) == _Static_tag(Value, as_float));
  auto same = (v.as_float == 1.5f);
  printf("tag %d float %d same %d\n", tag_of(v), is_float, same);

  printf("sizeof %d\n", (int)sizeof(Value));
  
  return 0;
}
