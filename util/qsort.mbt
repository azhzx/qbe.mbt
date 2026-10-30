///|
/// Unstable quicksort that reproduces the C `qsort` the reference relies on:
/// median-of-three at lo/mid/hi, the pivot moved to the end, and a Hoare
/// partition. Where a comparator can return 0 for distinct elements, the
/// resulting order of equal keys is part of the observable behaviour (phi
/// order in a block, slot order, spill priority), so it has to match the C
/// library's, not merely be a valid sort.
pub fn[T] qsort_c(a : Array[T], cmp : (T, T) -> Int32) -> Unit {
  qsort_c_n(a, a.length(), cmp)
}

///|
/// Sort the first n elements of a, leaving the rest untouched, the way a C
/// qsort call on a subrange would.
pub fn[T] qsort_c_n(a : Array[T], n : Int32, cmp : (T, T) -> Int32) -> Unit {
  if n < 2 {
    return
  }
  qsort_c_range(a, cmp, 0, n - 1)
}

///|
fn[T] qsort_c_range(
  a : Array[T],
  cmp : (T, T) -> Int32,
  lo : Int32,
  hi : Int32,
) -> Unit {
  if lo >= hi {
    return
  }
  let mid = lo + (hi - lo) / 2
  // median of three at lo, mid, hi
  if cmp(a[mid], a[lo]) < 0 {
    a.swap(mid, lo)
  }
  if cmp(a[hi], a[lo]) < 0 {
    a.swap(hi, lo)
  }
  if cmp(a[hi], a[mid]) < 0 {
    a.swap(hi, mid)
  }
  // move pivot to the end
  a.swap(mid, hi)
  let p = hi
  let mut i = lo
  let mut j = hi - 1
  while true {
    while i <= j && cmp(a[i], a[p]) < 0 {
      i = i + 1
    }
    while j >= i && cmp(a[j], a[p]) > 0 {
      j = j - 1
    }
    if i >= j {
      break
    }
    a.swap(i, j)
    i = i + 1
    j = j - 1
  }
  a.swap(i, p)
  qsort_c_range(a, cmp, lo, i - 1)
  qsort_c_range(a, cmp, i + 1, hi)
}
