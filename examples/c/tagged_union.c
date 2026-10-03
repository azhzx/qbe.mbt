// tagged
#include <stdio.h>

_Tagged_union Value {
  int as_int;
  float as_float;
};

static int tag_of(_Tagged_union Value v) { return (int)_Tag_of(v); }

int main(void) {
  _Tagged_union Value v = { .as_int = 100 };
  printf("tag %d int %d\n", tag_of(v), v.as_int);

  v.as_float = 1.5f; /* also sets the tag */
  int is_float = (_Tag_of(v) == _Get_tag(_Tagged_union Value, as_float));
  int same = (v.as_float == 1.5f);
  printf("tag %d float %d same %d\n", tag_of(v), is_float, same);

  printf("sizeof %d\n", (int)sizeof(_Tagged_union Value));
  return 0;
}
