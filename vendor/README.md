# vendor

This directory holds the reference material the port is checked against, plus
a pointer to the C front end.

## qbe/ - the reference QBE, pinned

`qbe/` is a git submodule. It is the reference implementation this repository
reimplements: the differential tests build it and compare its IR and assembly
with ours, byte for byte.

- pinned commit: the submodule commit recorded in this repository;
- mirror it is pinned from: https://github.com/ripe-lang/qbe.git (a fork that
  carries the build tweaks the tests need);
- **original upstream: https://c9x.me/git/qbe.git** - this is the project by
  Quentin Carbonneaux that everything here derives from. It is listed here for
  provenance: the pinned commit is a fork commit, and c9x.me does not serve
  it, so the submodule is fetched from the mirror.

```sh
git submodule update --init vendor/qbe
make -C vendor/qbe            # the reference binary the tests compare against
```

## qiang - the C front end (not vendored)

`qiang` is a symlink to the sibling checkout of the C front end, which became
its own project when it moved out of this repository:

- repository: https://github.com/azhzx/qiang.git
- package: https://mooncakes.io/docs/azhzx/qiang

It depends on this repository for the IR types, and a `moon.work` workspace in
the Qiang checkout resolves that dependency from the sibling directory. See
its README for the bootstrap step.