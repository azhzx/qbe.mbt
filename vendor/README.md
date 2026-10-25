# vendor

This directory holds the reference material the port is checked against, plus
a pointer to the C front end.

## qbe/ - the reference QBE, pinned

`qbe/` is a git submodule: the reference implementation this repository
reimplements. The differential tests build it and compare its IR and assembly
with ours, byte for byte.

- **original project: git://c9x.me/qbe.git** - QBE by Quentin Carbonneaux,
  everything here derives from it. Its master is e786f06, which is the base of
  the pin below.
- pinned commit: the submodule commit recorded in this repository. It is
  e786f06 plus two build commits that the tests need (an -O2 tweak and its
  merge), i.e. upstream master with a fork on top.
- fetched from: https://github.com/ripe-lang/qbe.git, a mirror of the fork, so
  that `git submodule update` works everywhere; c9x.me serves only git:// and
  does not publish the fork commits.

```sh
git submodule update --init vendor/qbe
make -C vendor/qbe            # the reference binary the tests compare against
```

To build the untouched upstream instead, clone it and point the tests at it:

```sh
git clone git://c9x.me/qbe.git qbe-upstream
make -C qbe-upstream
```

## qiang - the C front end (not vendored)

`qiang` is a symlink to the sibling checkout of the C front end, which became
its own project when it moved out of this repository:

- repository: https://github.com/azhzx/qiang.git
- package: https://mooncakes.io/docs/azhzx/qiang

It depends on this repository for the IR types, and a `moon.work` workspace in
the Qiang checkout resolves that dependency from the sibling directory. See
its README for the bootstrap step.