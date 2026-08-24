///|
// Comparison code negation (C cmpneg in util.c, via cmptab).

///|
pub fn cmpneg(c : Int) -> Int {
  match c {
    0 => 1
    1 => 0
    2 => 5
    3 => 4
    4 => 3
    5 => 2
    6 => 9
    7 => 8
    8 => 7
    9 => 6
    // CmpF: Cfeq=0, Cfge=1, Cfgt=2, Cfle=3, Cflt=4, Cfne=5, Cfo=6, Cfuo=7
    10 => 15 // NCmpI+Cfeq -> NCmpI+Cfne
    11 => 14 // NCmpI+Cfge -> NCmpI+Cflt
    12 => 13 // NCmpI+Cfgt -> NCmpI+Cfle
    13 => 12 // NCmpI+Cfle -> NCmpI+Cfgt
    14 => 11 // NCmpI+Cflt -> NCmpI+Cfge
    15 => 10 // NCmpI+Cfne -> NCmpI+Cfeq
    16 => 17 // NCmpI+Cfo -> NCmpI+Cfuo
    17 => 16 // NCmpI+Cfuo -> NCmpI+Cfo
    _ => abort("invalid comparison")
  }
}
