use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::bignum_test::{Fq, Fqq};
use crate::fields::bn254Fq::BNParams as BNParams;

// Simple schoolbook multiplication without any reduction
fn schoolbook_mult<N>(a: [Field; N], b: [Field; N]) -> ArrayX<Field, N, 2> {
  let mut res = ArrayX { segments: [[0;N], [0; N]] };
  for i in 0..N {
    for j in 0..N {
      res.add_assign(i+j, a[i] * b[j]);
    }
  }
  res
}

// Simple addition of limbs without any reduction
fn add_arrays<N>(a: [Field; N], b: [Field; N]) -> [Field;N] {
  let mut res = [0;N];
  for i in 0..N {
    res[i] = a[i]+b[i];
  }
  res
}

// Simple subtraction of limbs without any reduction
// FIXME can underflow?
fn subtract_arrays<N>(a: ArrayX<Field, N, 2>, b: ArrayX<Field, N, 2>, c: ArrayX<Field, N, 2>) -> ArrayX<Field, N, 2> {
  let mut res = ArrayX { segments: [[0;N], [0; N]] };
  for i in 0..2 {
    for j in 0..N {
      // FIXME this can underflow
      res.segments[i][j] = a.segments[i][j] - b.segments[i][j] - c.segments[i][j]; 
    }
  }
  res
}

// Karatsuba multiplication fixed for 9 limbs
// FIXME 
fn karatsuba_mult_9(a: [Field; 9], b: [Field; 9]) -> ArrayX<Field, 9, 2> {
  // a = [a_lo, a_hi], b = [b_lo, b_hi]
  // r0 = a_lo * b_lo
  // r2 = a_hi * b_hi
  // r1 = (a_lo+a_hi)(b_lo+b_hi) - r0 - r2
  //    = a_lo*b_lo + a_lo*b_hi + a_hi*b_lo + a_hi*b_hi - a_lo*b_lo - a_hi*b_hi
  //    = a_lo*b_hi + a_hi*b_lo
  // r0 -> low terms, r1 -> middle terms, r2 -> high terms
  // c = [r0_lo, r0_hi + r1_lo, r1_hi + r2_lo, r2_hi]

  // Fill 4 "lo" elements, but in a len 5 array
  // We work with the same type for consequent functions
  let mut a_lo = [0;5];
  let mut a_hi = [0;5];
  let mut b_lo = [0;5];
  let mut b_hi = [0;5];

  for i in 0..4 {
    a_lo[i] = a[i];
    b_lo[i] = b[i];
  }
  for i in 4..9 {
    a_hi[i-4] = a[i];
    b_hi[i-4] = b[i];
  }

  // r0, r1, r2 are all of the same type for next operations
  // r0 has 8 limbs filled
  let r0: ArrayX<Field, 5, 2> = schoolbook_mult(a_lo, b_lo);
  // r2 has 9 limbs filled
  let r2: ArrayX<Field, 5, 2> = schoolbook_mult(a_hi, b_hi);

  let added_a = add_arrays(a_lo, a_hi);
  let added_b = add_arrays(b_lo, b_hi);
  // r2 has 9 limbs filled
  let mut r1: ArrayX<Field, 5, 2> = schoolbook_mult(added_a, added_b);
  r1 = subtract_arrays(r1, r0, r2);

  // Result has 18 limbs
  let mut res = ArrayX { segments: [[0;9], [0;9]] };
  
  for i in 0..9 {
      // Low part
      res.add_assign(i, r0.get(i));
      // Overlapping part
      res.add_assign(i+4, r1.get(i));
      // High part
      res.add_assign(i+9, r2.get(i));
  }
  res
}

fn karatsuba_mult_18(a: [Field; 18], b: [Field; 18]) -> ArrayX<Field, 18, 2> {
  let mut a_lo = [0;9];
  let mut a_hi = [0;9];
  let mut b_lo = [0;9];
  let mut b_hi = [0;9];

  for i in 0..9 {
    a_lo[i] = a[i];
    b_lo[i] = b[i];
  }
  for i in 9..18 {
    a_hi[i-9] = a[i];
    b_hi[i-9] = b[i];
  }

// TODO change to karatsuba_9 (but this gives an error now)
  let r0: ArrayX<Field, 9, 2> = schoolbook_mult(a_lo, b_lo);
  let r2: ArrayX<Field, 9, 2> = schoolbook_mult(a_hi, b_hi);

  let added_a = add_arrays(a_lo, a_hi);
  let added_b = add_arrays(b_lo, b_hi);
  // Results in 17 limbs
  let mut r1: ArrayX<Field, 9, 2> = schoolbook_mult(added_a, added_b);
  r1 = subtract_arrays(r1, r0, r2);

  let mut res = ArrayX { segments: [[0;18], [0;18]] };
  
  for i in 0..17 {
    res.add_assign(i, r0.get(i));
    res.add_assign(i+9, r1.get(i));
    res.add_assign(i+18, r2.get(i));
  }
  res
}

#[test]
fn test_karatsuba_mult() {
    let a: Fqq = BigNum::__derive_from_seed([1, 2, 3, 4]);
    let b: Fqq = BigNum::__derive_from_seed([4, 5, 6, 7]);

    let c_schoolbook = schoolbook_mult(a.limbs, b.limbs);
    let c_karatsuba = karatsuba_mult_18(a.limbs, b.limbs);
    let c_karatsuba_rev = karatsuba_mult_18(b.limbs, a.limbs);
    println(c_schoolbook);
    println(c_karatsuba);
    assert(c_schoolbook == c_karatsuba);
    assert(c_karatsuba == c_karatsuba_rev);
}

#[test]
fn test_schoolbook_mult(){
  // Fq and Fqq are testfields defined in bignum_test
  // 3 and 18 limbs respectively

    let a: Fq = BigNum::__derive_from_seed([1, 2, 3, 4]);
    let b: Fq = BigNum::__derive_from_seed([4, 5, 6, 7]);

    let c = schoolbook_mult(a.limbs, b.limbs);
    let c_rev = schoolbook_mult(b.limbs, a.limbs);
    // println(c);
    // println(c_rev);
    assert(c == c_rev);

    let a: Fqq = BigNum::__derive_from_seed([1, 2, 3, 4]);
    let b: Fqq = BigNum::__derive_from_seed([4, 5, 6, 7]);

    let c = schoolbook_mult(a.limbs, b.limbs);
    let c_rev = schoolbook_mult(b.limbs, a.limbs);
    // println(c);
    // println(c_rev);
    assert(c == c_rev);
    
    // Check a*1 == a and 1*b == b
    let one: Fqq = BigNum::one();

    assert(schoolbook_mult(a.limbs, one.limbs).segments[0] == a.limbs);
    assert(schoolbook_mult(a.limbs, one.limbs).segments[1] == BigNum::new().limbs);
    
    assert(schoolbook_mult(one.limbs, b.limbs).segments[0] == b.limbs);
    assert(schoolbook_mult(b.limbs, one.limbs).segments[1] == BigNum::new().limbs);
}
