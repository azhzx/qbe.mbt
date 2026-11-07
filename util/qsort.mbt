///|
// A transcription of the C library's qsort/heapsort that the reference QBE
// binary uses (Apple libc's FreeBSD qsort.c + heapsort.c, Bentley & McIlroy).
// The resulting order of equal keys is part of the observable output (phi
// order in a block, spill priority), so the algorithm - including the
// insertion-sort/quick/median-of-3/heapsort structure and its tie behaviour -
// has to match, not merely produce a valid sort.

///|
fn[T] qsort_swap(a : Array[T], i : Int32, j : Int32) -> Unit {
  if i != j {
    let t = a[i]
    a[i] = a[j]
    a[j] = t
  }
}

///|
fn[T] qsort_vecswap(a : Array[T], i : Int32, j : Int32, n : Int32) -> Unit {
  for k in 0..<n {
    qsort_swap(a, i + k, j + k)
  }
}

///|
// C med3: return the index of the median of a[x], a[y], a[z].
fn[T] qsort_med3(
  a : Array[T],
  cmp : (T, T) -> Int32,
  x : Int32,
  y : Int32,
  z : Int32,
) -> Int32 {
  if cmp(a[x], a[y]) < 0 {
    if cmp(a[y], a[z]) < 0 {
      y
    } else if cmp(a[x], a[z]) < 0 {
      z
    } else {
      x
    }
  } else if cmp(a[y], a[z]) > 0 {
    y
  } else if cmp(a[x], a[z]) < 0 {
    x
  } else {
    z
  }
}

///|
// C flsl(n) for n > 0: number of significant bits.
fn qsort_fls(n : Int32) -> Int32 {
  let mut n = n
  let mut r = 0
  while n > 0 {
    r = r + 1
    n = n >> 1
  }
  r
}

///|
// C _isort with an optional swap limit (0 means no limit). Returns false when
// the limit is exceeded.
fn[T] qsort_isort(
  a : Array[T],
  cmp : (T, T) -> Int32,
  lo : Int32,
  n : Int32,
  swap_limit : Int32,
) -> Bool {
  let mut swap_cnt = 0
  for pm in 1..<n {
    let mut pl = pm
    while pl > 0 && cmp(a[lo + pl - 1], a[lo + pl]) > 0 {
      qsort_swap(a, lo + pl, lo + pl - 1)
      if swap_limit != 0 {
        swap_cnt = swap_cnt + 1
        if swap_cnt > swap_limit {
          return false
        }
      }
      pl = pl - 1
    }
  }
  true
}

///|
// C heapsort over n elements starting at lo. Elements are numbered from 1,
// exactly like the C macros, so the heap parent/child arithmetic matches.
fn[T] qsort_heapsort(
  a : Array[T],
  cmp : (T, T) -> Int32,
  lo : Int32,
  n0 : Int32,
) -> Unit {
  if n0 <= 1 {
    return
  }
  let mut nmemb = n0
  // CREATE over the initial heap.
  let mut l = nmemb / 2 + 1
  while true {
    l = l - 1
    if l <= 0 {
      break
    }
    let initval = l
    let mut par_i = initval
    while par_i * 2 <= nmemb {
      let mut child_i = par_i * 2
      let mut child = lo + child_i - 1
      if child_i < nmemb && cmp(a[child], a[child + 1]) < 0 {
        child = child + 1
        child_i = child_i + 1
      }
      let par = lo + par_i - 1
      if cmp(a[child], a[par]) <= 0 {
        break
      }
      qsort_swap(a, par, child)
      par_i = child_i
    }
  }
  // SELECT for every element: save the top, move the last element up and
  // sift the saved element down.
  while nmemb > 1 {
    let k = a[lo + nmemb - 1]
    a[lo + nmemb - 1] = a[lo]
    nmemb = nmemb - 1
    // Sift: copy the larger child up until k fits.
    let mut par_i = 1
    while par_i * 2 <= nmemb {
      let mut child_i = par_i * 2
      let mut child = lo + child_i - 1
      if child_i < nmemb && cmp(a[child], a[child + 1]) < 0 {
        child = child + 1
        child_i = child_i + 1
      }
      let par = lo + par_i - 1
      a[par] = a[child]
      par_i = child_i
    }
    let mut child_i = par_i
    while true {
      let par_i2 = child_i / 2
      let child = lo + child_i - 1
      let par = lo + par_i2 - 1
      if child_i == 1 || cmp(k, a[par]) < 0 {
        a[child] = k
        break
      }
      a[child] = a[par]
      child_i = par_i2
    }
  }
}

///|
fn[T] qsort_rec(
  a : Array[T],
  cmp : (T, T) -> Int32,
  lo : Int32,
  n : Int32,
  depth_limit : Int32,
) -> Unit {
  if depth_limit <= 0 {
    qsort_heapsort(a, cmp, lo, n)
    return
  }
  let depth_limit = depth_limit - 1
  if n <= 7 {
    let _ = qsort_isort(a, cmp, lo, n, 0)
    return
  }
  let mut swap_cnt = false
  let mut pl = lo
  let mut pm = lo + n / 2
  let mut pn = lo + n - 1
  if n > 40 {
    let d = n / 8
    pl = qsort_med3(a, cmp, pl, pl + d, pl + 2 * d)
    pm = qsort_med3(a, cmp, pm - d, pm, pm + d)
    pn = qsort_med3(a, cmp, pn - 2 * d, pn - d, pn)
  }
  pm = qsort_med3(a, cmp, pl, pm, pn)
  qsort_swap(a, lo, pm)
  let mut pa = lo + 1
  let mut pb = lo + 1
  let mut pc = lo + n - 1
  let mut pd = lo + n - 1
  while true {
    let mut cr = 0
    while pb <= pc {
      cr = cmp(a[pb], a[lo])
      if cr > 0 {
        break
      }
      if cr == 0 {
        swap_cnt = true
        qsort_swap(a, pa, pb)
        pa = pa + 1
      }
      pb = pb + 1
    }
    while pb <= pc {
      cr = cmp(a[pc], a[lo])
      if cr < 0 {
        break
      }
      if cr == 0 {
        swap_cnt = true
        qsort_swap(a, pc, pd)
        pd = pd - 1
      }
      pc = pc - 1
    }
    if pb > pc {
      break
    }
    qsort_swap(a, pb, pc)
    swap_cnt = true
    pb = pb + 1
    pc = pc - 1
  }
  let pe = lo + n
  let mut d1 = pa - lo
  let x = pb - pa
  if x < d1 {
    d1 = x
  }
  qsort_vecswap(a, lo, pb - d1, d1)
  let mut d2 = pd - pc
  let y = pe - pd - 1
  if y < d2 {
    d2 = y
  }
  qsort_vecswap(a, pb, pe - d2, d2)
  if !swap_cnt {
    let r = 1 + n / 4
    if qsort_isort(a, cmp, lo, n, r) {
      return
    }
  }
  let d1 = pb - pa
  let d2 = pd - pc
  if d1 <= d2 {
    if d1 > 1 {
      qsort_rec(a, cmp, lo, d1, depth_limit)
    }
    if d2 > 1 {
      qsort_rec(a, cmp, pe - d2, d2, depth_limit)
    }
  } else {
    if d2 > 1 {
      qsort_rec(a, cmp, pe - d2, d2, depth_limit)
    }
    if d1 > 1 {
      qsort_rec(a, cmp, lo, d1, depth_limit)
    }
  }
}

///|
/// Sort array a the way the reference C library does (see the file comment).
pub fn[T] qsort_c(a : Array[T], cmp : (T, T) -> Int32) -> Unit {
  qsort_c_n(a, a.length(), cmp)
}

///|
/// Sort the first n elements of a, leaving the rest untouched.
pub fn[T] qsort_c_n(a : Array[T], n : Int32, cmp : (T, T) -> Int32) -> Unit {
  if n < 2 {
    return
  }
  // C qsort: _qsort(..., DEPTH(n)) with DEPTH(x) = 2 * (flsl(x) - 1).
  let depth = 2 * (qsort_fls(n) - 1)
  qsort_rec(a, cmp, 0, n, depth)
}
