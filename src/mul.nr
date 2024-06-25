use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::bignum_test::{Fq, Fqq};
use crate::fields::bn254Fq::BNParams as BNParams;
use crate::BigNumParamsTrait;

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
// Note; this doesn't take care of underflow of certain limbs
fn subtract_arrays<N>(a: ArrayX<Field, N, 2>, b: ArrayX<Field, N, 2>, c: ArrayX<Field, N, 2>) -> ArrayX<Field, N, 2> {
  let mut res = ArrayX { segments: [[0;N], [0; N]] };
  for i in 0..2 {
    for j in 0..N {
      res.segments[i][j] = a.segments[i][j] - b.segments[i][j] - c.segments[i][j]; 
    }
  }
  res
}

// Karatsuba multiplication fixed for 9 limbs
// the limbs have max 120 bits
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
  // r0 has 7 limbs filled
  let r0: ArrayX<Field, 5, 2> = schoolbook_mult(a_lo, b_lo);
  // r2 has 9 limbs filled
  let r2: ArrayX<Field, 5, 2> = schoolbook_mult(a_hi, b_hi);
  let added_a = add_arrays(a_lo, a_hi);
  let added_b = add_arrays(b_lo, b_hi);
  // r2 has 9 limbs filled
  let mut r1: ArrayX<Field, 5, 2> = schoolbook_mult(added_a, added_b);
  // we know that r1-r0-r2 >= 0 so this subtraction is possible
  // but individual limbs might become negative, however, when adding
  // result together they become positive again
  r1 = subtract_arrays(r1, r0, r2);

  // Result has 18 limbs, of which the last will be 0
  let mut res = ArrayX { segments: [[0;9], [0;9]] };
  
  // r0 -> low terms, r1 -> middle terms, r2 -> high terms
  // c = [r0_lo, r0_hi + r1_lo, r1_hi + r2_lo, r2_hi]
  for i in 0..9 {
      // Low part
      res.add_assign(i, r0.get(i));
      // Overlapping part
      res.add_assign(i+4, r1.get(i));
      // High part
      res.add_assign(i+8, r2.get(i));
  }
  res
}

// Karatsuba multiplication fixed for 18 limbs
// the limbs have max 120 bits
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

  // a_lo, a_lo have 9 limbs of 120 bits
  // r0, r2 have 17 limbs of 240+log(17) bits
  let r0: ArrayX<Field, 9, 2> = karatsuba_mult_9(a_lo, b_lo);
  let r2: ArrayX<Field, 9, 2> = karatsuba_mult_9(a_hi, b_hi);

  // added_a, added_b have 9 limbs of 121 bits
  let added_a = add_arrays(a_lo, a_hi);
  let added_b = add_arrays(b_lo, b_hi);
  // r1 has 17 limbs of 242+log(17) bits
  let mut r1: ArrayX<Field, 9, 2> = karatsuba_mult_9(added_a, added_b);
  r1 = subtract_arrays(r1, r0, r2);

  let mut res = ArrayX { segments: [[0;18], [0;18]] };
  
  for i in 0..17 {
    res.add_assign(i, r0.get(i));
    res.add_assign(i+9, r1.get(i));
    res.add_assign(i+18, r2.get(i));
  }
  res
}

struct Test1080Params {}
impl BigNumParamsTrait<9> for Test1080Params {
    // FIXME incorrect values
    fn modulus() -> [Field; 9] {[
        0x0000000000000000000000000000000000c0a197a5ae0fcdceb052c9732614fe,
        0x0000000000000000000000000000000000656ae034423283422243918ab83be3,
        0x00000000000000000000000000000000006bf590da48a7c1070b7d5aabaac678,
        0x00000000000000000000000000000000000cce39f530238b606f24b296e2bda9,
        0x000000000000000000000000000000000001e1fef9bb9c1c3ead98f226f1bfa0,
        0x0000000000000000000000000000000000ad8c1c816e12e0ed1379055e373abf,
        0x0000000000000000000000000000000000cebe80e474f753aa9d1461c435123d,
        0x0000000000000000000000000000000000aee5a18ceedef88d115a8b93c167ad,
        0x0000000000000000000000000000000000268ba83c4a65c4307427fc495d9e44
    ]}
    // FIXME incorrect values
    fn double_modulus() -> [Field; 9] {[
        0x000000000000000000000000000000000081432f4b5c1f9b9d60a592e64c29fc,
        0x0000000000000000000000000000000000cad5c06884650684448723157077c7,
        0x0000000000000000000000000000000000d7eb21b4914f820e16fab557558cf0,
        0x0000000000000000000000000000000000199c73ea604716c0de49652dc57b52,
        0x000000000000000000000000000000000003c3fdf37738387d5b31e44de37f40,
        0x00000000000000000000000000000000005b183902dc25c1da26f20abc6e757e,
        0x00000000000000000000000000000000009d7d01c8e9eea7553a28c3886a247b,
        0x00000000000000000000000000000000005dcb4319ddbdf11a22b5172782cf5b,
        0x00000000000000000000000000000000004d17507894cb8860e84ff892bb3c89
    ]}
    // FIXME incorrect values
    fn redc_param() -> [Field; 9] {[
        0x000000000000000000000000000000000091697def7100cd5cf8d890b4ef2ec3,
        0x00000000000000000000000000000000006765ba8304214dac764d3f4adc3185,
        0x000000000000000000000000000000000048404bd14d927ea230e60d4bebf940,
        0x00000000000000000000000000000000007c4d53a23bacc251ecbfc4b7ba5a0b,
        0x000000000000000000000000000000000093eaf3499474a6f5b2fff83f1259c8,
        0x00000000000000000000000000000000005bff4c737b97281f1a5f2384a8c16d,
        0x000000000000000000000000000000000061b4cf2f55358476b5323782999055,
        0x00000000000000000000000000000000001e7a804e8eacfe3a2a5673bc3885b8,
        0x0000000000000000000000000000000000eabadeae4282906c817adf70eab4ae
    ]}
    fn k() -> u64 {
        1080
    }
    fn modulus_bits() -> u64 {
        1080
    }
}

// For direct testing of karatsuba for length 9
type Fq9 = BigNum<9, Test1080Params>;

#[test]
fn test_karatsuba_mult_9() {
    let a: Fq9 = BigNum::__derive_from_seed([1, 2, 3, 4]);
    let b: Fq9 = BigNum::__derive_from_seed([4, 5, 6, 7]);

    let c_schoolbook = schoolbook_mult(a.limbs, b.limbs);
    let c_karatsuba = karatsuba_mult_9(a.limbs, b.limbs);
    let c_karatsuba_rev = karatsuba_mult_9(b.limbs, a.limbs);

    assert(c_schoolbook == c_karatsuba);
    assert(c_karatsuba == c_karatsuba_rev);
}

#[test]
fn test_karatsuba_mult_18() {
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
