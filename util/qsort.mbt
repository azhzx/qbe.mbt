///|
// Unstable quicksort over Int arrays, emulating the C qsort used by the
// reference binary (median-of-three, Hoare partition, pivot at the end).
// cmp returns negative if a should sort before b.
pub fn qsort_int(
  a : Array[Int],
  lo : Int,
  hi : Int,
  cmp : (Int, Int) -> Int,
) -> Unit {
  if lo >= hi {
    return
  }
  let mid = lo + (hi - lo) / 2
  // median of three at lo, mid, hi
  if cmp(a[mid], a[lo]) < 0 {
    swap_int(a, mid, lo)
  }
  if cmp(a[hi], a[lo]) < 0 {
    swap_int(a, hi, lo)
  }
  if cmp(a[hi], a[mid]) < 0 {
    swap_int(a, hi, mid)
  }
  // move pivot to the end
  swap_int(a, mid, hi)
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
    swap_int(a, i, j)
    i = i + 1
    j = j - 1
  }
  swap_int(a, i, p)
  qsort_int(a, lo, i - 1, cmp)
  qsort_int(a, i + 1, hi, cmp)
}

///|
fn swap_int(a : Array[Int], i : Int, j : Int) -> Unit {
  let t = a[i]
  a[i] = a[j]
  a[j] = t
}
