use crate::utils::{gt, lt, to_U128};
use crate::test_utils::{assert_equal, print_bigint};
use dep::std::field::bn254::decompose;
use dep::std::ops::{Add, Sub, Mul, Div, Rem, BitOr, BitAnd, BitXor, Shl, Shr};
use dep::std::cmp::{Eq, Ord, Ordering};
use dep::std::bigint::Bn254Fr;
// BigInt arithmetic

// Number of bits for each limb. With respect to Noir implementation, this
// represents d.
global LIMB_BITS: Field = 120;
// The maximum value for a limb is 2^120
global MAX_VALUE_LIMB: Field = 0x100000000000000000000000000000000000000000000000000000000000000000000000000;
global pow127: U128 = U128::from_le_bytes([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

// A BigInt is represented in limbs of 120 bits
// Field has 254 bits
struct BigInt {
  limbs: Vec<Field>
}

impl BigInt {
    // Create a BigInt from slice
    fn from_slice(limbs: [Field]) -> Self {
        let limbs_vec = Vec::from_slice(limbs);
        BigInt { limbs: limbs_vec }
    }

    fn add_mod(self, other: Self, p: Self) -> Self {
        // Check if self and other has the same number of limbs.
        assert(self.limbs.len() == other.limbs.len());

        // Computes a + b such that each limb is at most 120 + 1 = 121 bits.
        let mut sum_a_b_limbs = Vec::new();
        for i in 0..self.limbs.len() {
            sum_a_b_limbs.push(self.limbs.get(i) + other.limbs.get(i))
        }

        // Obtain q and c such that a + b = q * p + c, where q == 0 or q == 1.
        let (q, c) = get_qc_add(self, other, p);

        // If q == 1, we constrain the condition a + b - p - c == 0. Otherwhise,
        // we constrain to a + b - c == 0.

        let mut reduced_limbs = Vec::new();

        if q == 0 {
            // Subtracting c from a + b.
            let (sub_limbs, _) = sub_reduced_limbs(sum_a_b_limbs, c.limbs);
            for i in 0..self.limbs.len() {
                reduced_limbs.push(sub_limbs.get(i));
            }
        } else if q == 1 {
            let mut sum_p_c_limbs = Vec::new();
            for i in 0..self.limbs.len() {
                sum_p_c_limbs.push(p.limbs.get(i) + c.limbs.get(i))
            }

            // Subtracting c from a + b.
            let (sub_limbs, _) = sub_reduced_limbs(sum_a_b_limbs, sum_p_c_limbs);
            for i in 0..self.limbs.len() {
                reduced_limbs.push(sub_limbs.get(i));
            }
        }

        // Assert if the following conditions hold:
        // 1. a, b, c have limbs of max 120 bits.
        // 2. a, b, c are smaller than p.
        // 3. q is zero or one.
        // 4. all limbs calculated in the subtraction are zero.

        // Step 1:
        // Asserting that a, b and c have the same number of limbs. For this, is
        // just enough to compare a and c, because we know that a and b have the
        // same number of limbs from the assertion at the beginning.
        assert(self.limbs.len() == c.limbs.len());

        // Then we assert that each limb of a, b, and c have 120 bits.
        for i in 0..self.limbs.len() {
            assert(!gt(self.limbs.get(i), MAX_VALUE_LIMB));
            assert(!gt(other.limbs.get(i), MAX_VALUE_LIMB));
            assert(!gt(c.limbs.get(i), MAX_VALUE_LIMB));
        }

        // We assert that a, b, c are smaller than p.
        for i in 0..self.limbs.len() {
            assert(lt(self.limbs.get(i), MAX_VALUE_LIMB));
            assert(lt(other.limbs.get(i), MAX_VALUE_LIMB));
            assert(lt(c.limbs.get(i), MAX_VALUE_LIMB));
        }

        // We assert that q == 0 or q == 1 by checking that q <= 1.
        assert(!gt(q, 1));

        // We assert that all the limbs in the subtraction are zero.
        for i in 0..self.limbs.len() {
            assert(reduced_limbs.get(i) == 0);
        }

        // Returns c as the final result of the addition mod p.
        c
    }

    fn zero() -> Self {
        let limbs_vec = Vec::from_slice(&[0]);
        BigInt { limbs: limbs_vec }
    }
}

// Subtracts p from res_limbs in such a way that the limbs in the result have
// d = 120 limbs. Also, the function returns a boolean that tells wether the 
// subtraction was interrupted in the middle of the computation. 
pub fn sub_reduced_limbs(res_limbs: Vec<Field>, p: Vec<Field>) -> (Vec<Field>, bool) {
    // Initialize vector for the same length
    let mut reduced_limbs: Vec<Field> = Vec::new();
    for _ in 0..res_limbs.len() {
        reduced_limbs.push(0);
    }

    // For the following loop, we'd like to break out but this is not supported in
    // constrained function. Workaround is to keep a boolean. 
    // When it is clear that p is too large to subtract, we stop subtracting. 
    let mut stop_subtracting = false;

    // Per limb, try to subtract the corresponding entry of p, i.e a[i]+b[i]-p[i]
    // if it is too large, try to get a borrow from the higher limb a[i+1]+b[i+1]
    // and then compute result a[i]+b[i]+2^120-p[i] (because 120 bits per limb)
    // if that is not possible, we stop subtracting
    // Workaround for inverse loop
    for j in 0..res_limbs.len() {
        let i = res_limbs.len() - 1 - j;

        if !stop_subtracting { // Workaround for not being able to break out of loop
            // Check p[i] > res[i]
            if gt(p.get(i), res_limbs.get(i)) {
                // If this is the highest limb, we immediately know p cannot be subtracted
                // and break the loop
                if i == res_limbs.len() - 1 {
                    stop_subtracting = true; // work around instead of break
                } else {
                    let mut already_borrowed = false;
                    // Start looking for the next non-zero entry that can give a borrow
                    for k in (i + 1)..res_limbs.len() {
                        if !already_borrowed {
                            if gt(reduced_limbs.get(k), 0) {
                                // If entry is larger than 0, borrow 1 from there and perform the subtraction 
                                // borrow 1
                                reduced_limbs.slice[k] = reduced_limbs.get(k) - 1;
                                // if k is not i+1, fill the "in between" limbs with the value 2ˆ120-1
                                let diff = k - i;
                                if (diff > 1) {
                                    for l in 1..diff {
                                        reduced_limbs.slice[i+l] = 1329227995784915872903807060280344575;
                                    }
                                }

                                // The borrow of the higher limb has value 2ˆ120 in this limb
                                // 2ˆ120 is 1329227995784915872903807060280344576
                                reduced_limbs.slice[i] = 1329227995784915872903807060280344576 + res_limbs.get(i) - p.get(i);
                                already_borrowed = true;
                            }
                        }
                    }
                    stop_subtracting = !already_borrowed;
                }
            } else {
                // If p[i] <= res[i], we have easy subtraction: res[i] - p[i]
                reduced_limbs.slice[i] = res_limbs.get(i) - p.get(i);
            }
        }
    }

    (reduced_limbs, stop_subtracting)
}
fn larger(a: [u8], b: [u8]) -> bool {
    let mut res = false;
    let mut done = false;
    // Iterate using a loop and calculate the reverse index
    for j in 0..30 {
        let i = 29 - j;
        if !done {
            if a[i] > b[i] {
                res = true; // a is larger
            } else if a[i] < b[i] {
                done = true; // b is larger
            }
        }
    }
    res // a and b are equal
}

// radix-60
pub fn sub_reduced_limbs_fields(res_limbs: Vec<Field>, res_len: u64, p: Vec<Field>) -> (Vec<Field>, bool) {
    // Initialize vector for the same length
    let mut reduced_limbs: Vec<Field> = Vec::new();
    // let len = res_limbs.len();
    for _ in 0..res_len {
        reduced_limbs.push(0);
    }

    // For the following loop, we'd like to break out but this is not supported in
    // constrained function. Workaround is to keep a boolean. 
    // When it is clear that p is too large to subtract, we stop subtracting. 
    let mut stop_subtracting = false;

    // Per limb, try to subtract the corresponding entry of p, i.e a[i]+b[i]-p[i]
    // if it is too large, try to get a borrow from the higher limb a[i+1]+b[i+1]
    // and then compute result a[i]+b[i]+2^60-p[i] (because 120 bits per limb)
    // if that is not possible, we stop subtracting
    // Workaround for inverse loop
    for j in 0..res_len {
        let i = res_len - 1 - j;

        if !stop_subtracting { // Workaround for not being able to break out of loop
            // Check p[i] > res[i]
            // convert to 30 bytes and convert

            if larger(p.get(i).to_le_bytes(31), res_limbs.get(i).to_le_bytes(31)) {
                // If this is the highest limb, we immediately know p cannot be subtracted
                // and break the loop
                if i == res_len - 1 {
                    stop_subtracting = true; // work around instead of break
                } else {
                    let mut already_borrowed = false;
                    // Start looking for the next non-zero entry that can give a borrow
                    for k in (i + 1)..res_len {
                        if !already_borrowed {
                            if larger(reduced_limbs.get(k).to_le_bytes(31), 0.to_le_bytes(31)) {
                                // If entry is larger than 0, borrow 1 from there and perform the subtraction 
                                // borrow 1
                                reduced_limbs.slice[k] = reduced_limbs.get(k) - 1;
                                // if k is not i+1, fill the "in between" limbs with the value 2^60-1
                                let diff = k - i;
                                if (diff > 1) {
                                    for l in 1..diff {
                                        reduced_limbs.slice[i+l] = 1152921504606846975;
                                    }
                                }

                                // The borrow of the higher limb has value 60 in this limb
                                // 60 is 1152921504606846976
                                reduced_limbs.slice[i] = 1152921504606846976 + res_limbs.get(i) - p.get(i);
                                already_borrowed = true;
                            }
                        }
                    }
                    stop_subtracting = !already_borrowed;
                }
            } else {
                // If p[i] <= res[i], we have easy subtraction: res[i] - p[i]
                reduced_limbs.slice[i] = res_limbs.get(i) - p.get(i);
            }
        }
    }

    (reduced_limbs, stop_subtracting)
}

/*
Returns (q,c) with q is 0 or 1, which fulfills the following equality:
  a + b = q * p + c, where q is 0 or 1

Inputs: 
- a,b BigInts mod p with limbs of 120 bits
- modulus p, BigInt with limbs of 120 bits

Method:
1. Add all limbs of a and b
2. Try to subtract p. If this causes underflow, stop.
3. If p was subtracted, return (q=0, a+b). Else return (q=1, a+b-p)
*/
pub fn get_qc_add(a: BigInt, b: BigInt, p: BigInt) -> (Field, BigInt) {
    // In the final implementation this function can be unconstrained.
    // Then we constrain the equality a+b-p*q-c == 0
    // Currently if we make it unconstrained it throws an error:
    // Error: Slices cannot be returned from an unconstrained runtime to a constrained runtime
    // (Note that if we make it unconstrained, we can use break)

    // Check a & b have the same amount of limbs
    assert(a.limbs.len() == b.limbs.len());

    // Step 1. Add limbs of a and b
    let mut res_limbs = Vec::new();

    for i in 0..a.limbs.len() {
        // Since limbs of a & b have max 120 bits,
        // the addition has max 121 bits.
        // Thus the result fits in a Field type (which has 254 bits)
        let added_val = a.limbs.get(i) + b.limbs.get(i);
        res_limbs.push(added_val);
    }

    // Step 2. Try to subtract p, if possible
    let (reduced_limbs, stop_subtracting) = sub_reduced_limbs(res_limbs, p.limbs);

    // 3. If p was subtracted, return (q=0, a+b). Else return (q=1, a+b-p)

    // To find out whether p was subtracted, we compare res_limbs and reduced_limbs
    // If they are different, p might have been subtracted.
    let mut limbs_different = false;
    // Once again, this requires the limbs to have max 128 bits
    for i in 0..a.limbs.len() {
        if !limbs_different { // workaround instead of break
            if reduced_limbs.get(i) != res_limbs.get(i) {
                limbs_different = true;
            }
        }
    }

    // p was subtracted if res_limbs != reduced_limbs AND 
    // the subtraction of p was not interrupted
    if limbs_different & !stop_subtracting {
        // q = 1, c = a+b - p
        (1, BigInt { limbs: reduced_limbs })
    } else {
        // q = 0, c = a+b
        (0, BigInt { limbs: res_limbs })
    }
}

/*
Returns multiplication a*b without any reduction on the limbs.
If a has n limbs an b has m limbs, the result will have n+m-1 limbs. 

Performs standard schoolbook multiplication

This will work fine for <= 16384 limbs in the bigint. Reasoning:

Limb is 120 bits -> multiplication of 2 limbs is 240 bits
Adding x limbs of 240 limbs takes 240 + log_2(x) bits
Field has 254 bits
Solve for x: 254 = 240 + log_2(x)
x = 16384
So 16384 additions of multiplied limbs are possible before reducing is needed
*/
pub fn schoolbook_mult_no_reduction(a: BigInt, b: BigInt) -> BigInt {
    // assert(a.limbs.len() == b.limbs.len());

    let mut res_limbs = Vec::new();
    for _ in 0..(a.limbs.len() + b.limbs.len() - 1) {
        res_limbs.push(0);
    }
    for i in 0..a.limbs.len() {
        for j in 0..b.limbs.len() {
            res_limbs.slice[i+j] += a.limbs.get(i)*b.limbs.get(j);
        }
    }

    BigInt { limbs: res_limbs }
}

// Naive way to get U256 division going
struct U256 {
  lo: U128, // 128 lower bits
  hi: U128 // 128 higher bits
}

impl U256 {

    pub fn zero() -> U256 {
        U256 { lo: U128::zero(), hi: U128::zero() }
    }

    pub fn one() -> U256 {
        U256 { lo: U128::one(), hi: U128::zero() }
    }

    pub fn new(lo: U128, hi: U128) -> U256 {
        U256 { lo, hi }
    }

    pub fn from_U128(lo: U128) -> U256 {
        U256 { lo, hi: U128::zero() }
    }

    pub fn from_le_bytes(bytes: [u8; 32]) -> U256 {
        let mut low_bytes = [0;16];
        for i in 0..16 {
          low_bytes[i] = bytes[i];
        }
        let mut high_bytes = [0;16];
        for i in 0..16 {
          high_bytes[i] = bytes[i+16];
        }
        U256 { lo: U128::from_le_bytes(low_bytes), hi: U128::from_le_bytes(high_bytes) }
    }

    pub fn to_le_bytes(self: Self) -> [u8; 32] {
        let lo = self.lo.to_le_bytes();
        let hi = self.hi.to_le_bytes();
        let mut bytes = [0; 32];
        for i in 0..16 {
            bytes[i] = lo[i];
            bytes[i+16] = hi[i];
        }
        bytes
    }

    // Be careful with this one, because 256 won't always fit in the Field (254 bits)
    pub fn to_field(self: U256) -> Field {
        let lo = self.lo.to_integer();
        let hi = self.hi.to_integer() * 1329227995784915872903807060280344576;
        lo + hi
    }

    unconstrained fn unconstrained_div(self: Self, b: U256) -> (U256, U256) {
        if b == U256::zero() {
            (U256::zero(), U256::zero())
        } else if self < b {
            (U256::zero(), self)
        } else if self == b {
            (U256::one(), U256::zero())
        } else {
          let two = U256::new(U128::from_u64s_le(2, 0), U128:: zero());
            // Recursive call with doubled divisor
            let (q, r) = if b.hi >= pow127 {
                // Mult by 2 would overflow so we have to stop
                (U256::zero(), self)
            } else {
              self.unconstrained_div(b + b)
            };

            let q_mul_2 = q + q;
            
            if r < b {
                (q_mul_2, r)
            } else {
                (q_mul_2 + U256::one(), r - b)
            }
        }
    }
}

impl Add for U256 {
    fn add(self: Self, b: U256) -> U256 {
      // Convert to Field and add, this will fit
      // 128 bits + 128 bits, so max 1 bits of carry
        let low: Field = self.lo.to_integer() + b.lo.to_integer();
        // Carry is whatever overflow above 128 bits (16 bytes)
        let low_bytes = low.to_le_bytes(31);
        let mut reduced_low = [0;16];
        for i in 0..16 {
          reduced_low[i] = low_bytes[i];
        }
        let carry_byte = low_bytes[16];
        let low_reduced = U128::from_le_bytes(reduced_low);
        let carry = U128::from_u64s_le(carry_byte as u64, 0);

        // Convert all to Field to prevent overflow
        // 128 bits + 128 bits + 1 bits 
        let high: Field = self.hi.to_integer() + b.hi.to_integer() + carry.to_integer();
        let high_bytes = high.to_le_bytes(31);
        // We don't allow overflow
        assert(high_bytes[16] == 0, "attempt to add with overflow");

        let mut high_reduced = [0;16];
        for i in 0..16 {
          high_reduced[i]= high_bytes[i];
        }

        U256::new(low_reduced, U128::from_le_bytes(high_reduced))
    }
}

impl Sub for U256 {
    fn sub(self: Self, b: U256) -> U256 {
        assert(self.hi >= b.hi, "");
        if (b.lo > self.lo) {
            // 2^128 = 340282366920938463463374607431768211456
            let res_lo = 340282366920938463463374607431768211456 + self.lo.to_integer() - b.lo.to_integer();
            let res_lo_bytes = res_lo.to_le_bytes(16);
            assert(self.hi >= U128::one(), "");
            assert(self.hi - b.hi >= U128::one(), "");
            let hi: U128 = self.hi - U128::one() - b.hi;
            U256::new(U128::from_le_bytes(res_lo_bytes.as_array()), hi)
        } else if self.lo == b.lo {
            let hi: U128 = self.hi - b.hi;
            U256::new(U128::zero(), hi)
        } else {
            let hi: U128 = self.hi - b.hi;
            U256::new(self.lo - b.lo, hi)
        }
    }
}

impl Eq for U256 {
    fn eq(self: Self, b: U256) -> bool {
        (self.lo == b.lo) & (self.hi == b.hi)
    }
}

// 0, 1, and 2 for Lt, Eq, and Gt
// https://github.com/noir-lang/noir/blob/d9b4712bf1a62548dd7ed17b181882ae537d70dd/noir_stdlib/src/cmp.nr#L86C29-L86C59
impl Ord for U256 {
    fn cmp(self, other: Self) -> Ordering {
        let hi_ordering = self.hi.cmp(other.hi);
        let lo_ordering = self.lo.cmp(other.lo);

        if hi_ordering == Ordering::equal() {
            lo_ordering
        } else {
            hi_ordering
        }
    }
}

#[test]
fn test_unconstrained_div() {
    // Test Case 1: Simple Division
    // 10 / 2
    let a = U256::new(U128::from_u64s_le(10, 0), U128::zero());
    let b = U256::new(U128::from_u64s_le(2, 0), U128::zero());
    let (quotient, remainder) = a.unconstrained_div(b);
    let expected_quotient = U256::new(U128::from_u64s_le(5, 0), U128::zero());
    let expected_remainder = U256::zero();
    assert(quotient == expected_quotient);
    assert(remainder == expected_remainder);

    // Test Case 2: Division with Remainder
    // 10 / 3
    let a = U256::new(U128::from_u64s_le(10, 0), U128::zero());
    let b = U256::new(U128::from_u64s_le(3, 0), U128::zero());
    let (quotient, remainder) = a.unconstrained_div(b);
    let expected_quotient = U256::new(U128::from_u64s_le(3, 0), U128::zero());
    let expected_remainder = U256::new(U128::from_u64s_le(1, 0), U128::zero());
    assert(quotient == expected_quotient);
    assert(remainder == expected_remainder);

    // Test Case 3: Large Numbers Division
    // (2^128 + 1) / (2^64 + 1)
    // 340282366920938463463374607431768211457
    let a = U256::new(U128::one(), U128::one());
    let b = U256::new(U128::from_u64s_le(1, 1), U128::zero());
    let (quotient, remainder) = a.unconstrained_div(b);
    let expected_quotient = U256::new(U128::from_u64s_le(18446744073709551615, 0), U128::zero());
    let expected_remainder = U256::new(U128::from_u64s_le(2, 0), U128::zero());
    // quotient * (2^64+1) = 340282366920938463463374607431768211455
    // remainder = 2
    assert(quotient == expected_quotient);
    assert(remainder == expected_remainder);

    // Test Case 4: Division by Zero
    // 10 / 0
    let a = U256::new(U128::from_u64s_le(10, 0), U128::zero());
    let b = U256::zero();
    let (quotient, remainder) = a.unconstrained_div(b);
    let expected_quotient = U256::zero();
    let expected_remainder = U256::zero();
    assert(quotient == expected_quotient);
    assert(remainder == expected_remainder);
}

#[test]
fn test_cmp_u256() {
    // 2^128 + 1
    let a = U256::new(U128::one(), U128::one());
    // 1
    let b = U256::new(U128::one(), U128::zero());

    assert(!(a==b));
    assert(a==U256::new(U128::one(), U128::one()));

    // println(a.cmp(b));//2 greater than
    // println(a.cmp(a));//1 equal
}

#[test]
fn test_add_u256() {
    // 2^64 - 1
    let highest_u64 = 18446744073709551615;
    let highest_u128 = U128 { lo: highest_u64, hi: highest_u64 };
    let a = U256::new(highest_u128, U128::zero());
    let b = U256::new(U128::one(), U128 { lo: 4, hi: 5 });
    // println(a + b)
    // OK
}

#[test]
fn test_sub_u256_no_borrow() {
    // 2^128 + 1
    let a = U256::new(U128::one(), U128::one());
    // 1
    let b = U256::new(U128::one(), U128::zero());

    // 2^128 + 1 - 1
    // res should be 2^128
    let expected_lo = U128::zero();
    let expected_hi = U128::one();
    let expected = U256::new(expected_lo, expected_hi);

    let result = a.sub(b);

    assert(result.lo == U128::zero());
    assert(result.hi == U128::one());
}

#[test]
fn test_sub_u256_with_borrow() {
    // 2^128 + 1
    // {1,0}, {1,0}
    let a_lo = U128::one();
    let a_hi = U128::one();
    let a = U256::new(a_lo, a_hi);

    // 2^64 + 1
    // {1,1}, {0,0}
    let b_lo = U128::from_u64s_le(1, 1);
    let b = U256::new(b_lo, U128::zero());

    // Expected result: 2^128 - 2^64
    // 2^128
    // {0,0}, {1,0}
    // 2^64
    // - {0,1}, {0,0}
    // = 340282366920938463444927863358058659840 = 16^^ffffffffffffffff0000000000000000
    let expected_lo = U128::from_u64s_le(0x00, 0xFFFFFFFFFFFFFFFF);
    let expected_hi = U128::zero();
    let expected = U256::new(expected_lo, expected_hi);

    let result = a.sub(b);

    // Result should be 2^64 = {0,1}, {0,0}
    assert(result.hi == U128::zero());
    assert(result.lo == expected_lo);
}

// q,r
fn bigint_mod(a: U256, divisor: U256) -> (U128, U128) {
    let (quotient, remainder) = a.unconstrained_div(divisor); // Get the quotient

    // Now cast back to U128
    let mut q_array: [u8; 16] = [0; 16];
    let t_q = quotient.to_le_bytes();
    for i in 0..16 {
        // todo make more efficient
        q_array[i] = t_q[i];
    }

    let mut r_array: [u8; 16] = [0; 16];
    let r_q = remainder.to_le_bytes();
    for i in 0..16 {
        // todo make more efficient
        r_array[i] = r_q[i];
    }
    (U128::from_le_bytes(q_array), U128::from_le_bytes(r_array))
}

/*
Returns (q,c) BigInts in radix 120, which fulfills the following equality:
  a + b = q * p + c
Note that the limbs of c are not necessarily reduced
TODO: is this needed?

Inputs: 
- a,b BigInts mod p with limbs of 120 bits
- modulus p, BigInt with limbs of 120 bits

Method: Division algorithm in The Art of Computer Programming - Donald Knuth
4.3.1 Algorithm D
*/
pub fn get_qc_mult(a: BigInt, len_a: u64, b: BigInt, len_b: u64, p: BigInt) -> (BigInt, BigInt) {
    // u = a*b
    let mut u = schoolbook_mult_no_reduction(a, b);

    // assert(u.limbs.len() == (len_a + len_b - 1)); TODO
    let len_u = len_a + len_b - 1;

    // switch u
    // per coefficient we split it into 2
    let mut coeffs_u_radix60: Vec<Field> = Vec::new();
    for i in 0..len_u {
      // This is like 128 bits (why?)
      let bits = u.limbs.slice[i].to_le_bits(128);
      // Convert and push low part of the coefficient
      let mut lo_bits: [u1;60] = [0;60];
      let mut high_bits: [u1;68] = [0;68];
      for j in 0..60 {
        lo_bits[j] = bits[j];
      }
      let mut lo_field = 0;
      let mut base = 1;
      for k in 0..60 {
          lo_field += (lo_bits[k] as Field)*base;
          base *= 2;
      }
      coeffs_u_radix60.push(lo_field);

      // Convert and push high part of the coefficient
      for j in 0..68 {
        high_bits[j] = bits[j+60];
      }
      let mut high_field = 0;
      let mut base = 1;
      for k in 0..68 {
          high_field += (high_bits[k] as Field)*base;
          base *= 2;
      }
      coeffs_u_radix60.push(high_field);
    }

    // switch p to radix-60
    let mut coeffs_p_radix60: Vec<Field> = Vec::new();
    for i in 0..p.limbs.len() {
      // This is like 128 bits
      let bits = p.limbs.slice[i].to_le_bits(128);
      // Convert and push low part of the coefficient
      let mut lo_bits: [u1;60] = [0;60];
      let mut high_bits: [u1;68] = [0;68];
      for j in 0..60 {
        lo_bits[j] = bits[j];
      }
      let mut lo_field = 0;
      let mut base = 1;
      for k in 0..60 {
          lo_field += (lo_bits[k] as Field)*base;
          base *= 2;
      }
      coeffs_p_radix60.push(lo_field);

      // Convert and push high part of the coefficient
      for j in 0..68 {
        high_bits[j] = bits[j+60];
      }
      let mut high_field = 0;
      let mut base = 1;
      for k in 0..68 {
          high_field += (high_bits[k] as Field)*base;
          base *= 2;
      }
      coeffs_p_radix60.push(high_field);
    }

    let len_p = coeffs_p_radix60.len();
    // Chop off the top bytes that are 0 for p
    let mut stop = false;
    for i in 0..len_p-1 {
      if !stop {
        let j = len_p-1-i;
        if coeffs_p_radix60.slice[j] == 0 {
          coeffs_p_radix60.pop();
        } else {
          stop = true;
        }
      }
    }

    // If u is shorter than p, we can conclude q = 0 and c = a*b
    // TODO uncomment
    // if (u.limbs.len() < p.limbs.len()) {
    //     (BigInt::zero(), u)
    // }

    let len_u = coeffs_u_radix60.len();
    let n = coeffs_p_radix60.len();

    // Start Division algorithm
    // Following the algorithm, v = p.
    // D1

    // b = 2^60
    let b = to_U128(1152921504606846976);
    // d = floor(b/(v_{n-1}+1))
    // v_{n-1} is the most significant limb of p
    
    let temp: U128 = to_U128(coeffs_p_radix60.get(coeffs_p_radix60.len() - 1) + 1);
    // This does division with floor
    let d_u128: U128 = b / temp;
    let d: Field = d_u128.to_integer();

    for i in 0..coeffs_u_radix60.len() {
        // This won't overflow because limbs are 60 bits
        coeffs_u_radix60.slice[i] = coeffs_u_radix60.slice[i] * d;
    }
    let len_before = coeffs_u_radix60.len();

    // this won't make u longer so length is still 10
    let mut u = reduce_limbs_60bits(coeffs_u_radix60, len_before);
    let len_after = u.len();
    // We need an extra digit so u becomes of length m+n
    if len_after == len_before {
        u.insert(len_u, 0);
    }

    let mut p_limbs: Vec<Field> = Vec::new();
    for i in 0..coeffs_p_radix60.len() {
        p_limbs.push(coeffs_p_radix60.slice[i] * d);
    }
    p_limbs = reduce_limbs_60bits(p_limbs, p_limbs.len());

    // D2
    let m = len_before - p_limbs.len(); // The last added zero is extra

    let looplen = m+1;
    let mut q_vec = Vec::new();
    for _ in 0..8 {//FIXME this end range should be m+1
        q_vec.push(0);
    }

    let mut j = m;
    let looplen = m+1;
    // Workaround for reverse loop
    // The result is [q_0,q_1..q_{m}]
    for _ in 0..8 {//FIXME this end range should be m+1
        // D3
        let mut index_1 = n + j;

        // u.get(index_1) * d can be larger than 60 bits
        let u_j_n = U256::from_le_bytes((u.get(index_1) * b.to_integer()).to_le_bytes(32).as_array());
        let u_j_n_sub_1 = U256::from_le_bytes((u.get(index_1 - 1)).to_le_bytes(32).as_array());
        let temp1 = u_j_n + u_j_n_sub_1;        
        let p_bigint = U256::from_le_bytes(p_limbs.get(n - 1).to_le_bytes(32).as_array());
        let mut (q_head, r_head) = bigint_mod(temp1, p_bigint);

        // Note: q_head is never more than 2 in error.
        // Only perform this check if it doesn't trigger out of bound:

        // FIXME this all should be U256 arithmetic, because U128 can overflow.
        // d*p is already 120 bits (for radix-60)
        let mut check2 = false;
        if n >= 2 & index_1 >= 2 {
            let temp2 = q_head * to_U128(p_limbs.get(n - 2));
            let temp3 = b * r_head + to_U128(u.get(index_1 - 2));
            check2 = temp2 > temp3;
        }

        if q_head >= b | check2 {
            // TODO make this checked_sub
            q_head -= to_U128(1);
            r_head += to_U128(p_limbs.get(n - 1));
            if r_head < b {
                check2 = false;
                if n >= 2 & index_1 >= 2 {
                    let temp2 = q_head * to_U128(p_limbs.get(n - 2));
                    // TODO
                    let temp3 = b * r_head + to_U128(u.get(index_1 - 2));
                    check2 = temp2 > temp3;
                }
                if q_head >= b | check2 {
                    // TODO make this checked_sub
                    q_head -= to_U128(1);
                    r_head += to_U128(p_limbs.get(n - 1));
                }
            }
        }

        // D4
        if q_head.to_integer() != 0 {
            // Get [u_j,..,u_{j+n}]
            let mut u_j_limbs = Vec::new();
            for i in 0..(n+1) {
                u_j_limbs.push(u.get(j + i));
            }
            // Calculate [u_j,..,u_{j+n}] - q_head * [p_0,p_1,..,p_{n-1},0]
            // limbs of p have max 60 bits, so multiplication with q_head will fit with Field
            let mut q_head_p_limbs = Vec::new();

            for i in 0..n {
                // This calculation has to be done with enough space (Field)
                // p[n-1] can have 60+60=120 bits
                q_head_p_limbs.push(p_limbs.get(i) * q_head.to_integer());
            }
            q_head_p_limbs.push(0);

            // reduce limbs back to 60 bits
            q_head_p_limbs = reduce_limbs_60bits(q_head_p_limbs, q_head_p_limbs.len());

            let (res_limbs_segment, underflow) = sub_reduced_limbs_fields(u_j_limbs, n+1, q_head_p_limbs);

            if underflow {
                // TODO 
                // D6
                println(100);
            }

            // Set the updated limbs to the correct segment of u
            for i in 0..res_limbs_segment.len() {
                u.slice[j+i] = res_limbs_segment.slice[i];
            }
        }

        // D5
        q_vec.slice[j] = q_head.to_integer();

        // D7
        j -= 1;
    }

    // D8
    // quotient [q_0,q_1,..,q_m]
    // remainder [u_0,u_1,..,u_{n-1}] / d

    let res_q = BigInt { limbs: q_vec };

    let mut r_vec = Vec::new();
    for i in 0..n {
        r_vec.push((to_U128(u.slice[i]) / d_u128).to_integer());
    }
    let res_r = BigInt { limbs: r_vec };

    // TODO chop off the most significant coefficients as long as they are 0
    // implement function `normalize` (check num bigint Rust lib for reference)
    // TODO convert to radix-120
    (res_q, res_r) // this is radix 60
}

/*
Input limbs are in radix-60, but they might be up to 180 bits large
Returns reduces limbs all max 60 bits
*/
fn reduce_limbs_60bits(limbs: Vec<Field>, len: u64) -> Vec<Field> {
  // Per limb, we can have 2 carries
  let mut res: Vec<Field> = Vec::new();
  // Fill up with current coeffs first, so we can 
  // add carries in place
  for i in 0..len {
    res.push(limbs.slice[i]);
  }


  for i in 0..len {
    // Grab all bits of single limb
    let limb_bits = res.slice[i].to_le_bits(180);
    // Divide bits into 60 bits pieces
    let mut current: [u1;60] = [0;60];
    let mut carry1: [u1;60] = [0;60];
    let mut carry2: [u1;60] = [0;60];
    for j in 0..180 {
      if j < 60 {
        current[j] = limb_bits[j];
      } else if j <120 {
        carry1[j-60] = limb_bits[j];
      } else {
        carry2[j-120] = limb_bits[j];
      }
    }

    let mut current_field: Field = 0;
    let mut carry1_field: Field = 0;
    let mut carry2_field: Field = 0;
    let mut base = 1;
    for k in 0..60 {
        current_field += (current[k] as Field)*base;
        carry1_field += (carry1[k] as Field)*base;
        carry2_field += (carry2[k] as Field)*base;
        base *= 2;
    }
    
    // Now we have the 3 fields that represent the current limb
    // and the carries for the next fields
    // A field has 254 bits so we can do additions without problem
    res.slice[i] = current_field;

    // The the carries might fall outside of the original length of the array
    if (i+1) == res.len() {
      if carry2_field != 0 {
        res.push(carry1_field);
        res.push(carry2_field);
      } else if carry1_field != 0 {
        res.push(carry1_field);
      }
      
    } else if (i+2) == res.len() {
      res.slice[i+1] += carry1_field;
      if carry2_field != 0 {
        res.push(carry2_field);
      }
    } else {
      res.slice[i+1] += carry1_field;
      res.slice[i+2] += carry2_field;
    }
  }

  // position len+1 can have 61 bits,
  // position len+2 can have 60 bits
  // Only necessary if the previous reductions steps have resulted
  // in increasing the res vector

  if (len != res.len()) {
    let bits_coeff_len1 = res.slice[len].to_le_bits(61);
    // Reduce if needed
    if (bits_coeff_len1.len() > 60) {
      // There can be a single carry
      let carry = bits_coeff_len1[60];
      if (carry == 1) {
          if res.len() == len+2 {
            res.slice[len+1] += carry as Field;
            // Now this might need to carry
            let bits_coeff_len2 = res.slice[len+1].to_le_bits(61);
            let carry2 = bits_coeff_len2[60];
            if carry2 == 1 {
              res.push(carry2 as Field);  
            }
          } else {
            res.push(carry as Field);
          }
      }
    }
  }

  res
}

#[test]
fn test_reduction_radix60() {
  let mut testvalue: Vec<Field> = Vec::new();
  testvalue.push(0);
  testvalue.push(0);
  testvalue.push(0x0a3d70a3d70a3d65c28f5c28f5c290);
  testvalue.push(0);

  let res = reduce_limbs_60bits(testvalue, 4);
  assert(res.slice[0] == 0);
  assert(res.slice[1] == 0);
  assert(res.slice[2] == 0x05c28f5c28f5c290);
  assert(res.slice[3] == 0xa3d70a3d70a3d6);

}

// Reduce the limbs of a BigInt to 128 bits
// This can return a BigInt with len_a+1 if needed for carrying
fn reduce_limbs_128(a: &mut BigInt, len_a: u64) -> BigInt {
    let mut res_limbs = Vec::new();
    let mut carry = 0;
    for i in 0..len_a {
        let (lo, hi) = decompose(a.limbs.get(i));
        res_limbs.push(lo + carry);
        carry = hi;
    }
    if carry != 0 {
        res_limbs.push(carry);
    }
    BigInt { limbs: res_limbs }
}

fn reduce_limbs_128_vec(a: &mut Vec<Field>, len_a: u64) -> Vec<Field> {
    let mut res_limbs = Vec::new();
    let mut carry = 0;
    for i in 0..len_a {
        let (lo, hi) = decompose(a.get(i));
        res_limbs.push(lo + carry);
        carry = hi;
    }
    if carry != 0 {
        res_limbs.push(carry);
    }
    res_limbs
}

/*
Function: add_mod

Testcase: happy path with q == 1.
*/
#[test]
fn test_add_mod_q_1() {
    let mut a = BigInt::from_slice(&[2, 1, 0, 0]);
    let mut b = BigInt::from_slice(&[0, 1, 0, 0]);

    // This modulus should trigger reduction.
    // Subtracting p is easy, and doesn't require using any borrow
    let p = BigInt::from_slice(&[1, 2, 0, 0]);

    let c = a.add_mod(b, p);

    assert_equal(c.limbs, [1, 0, 0, 0].as_slice(), 4);
}

/*
Function: add_mod

Testcase: happy path with q == 0, and with no reduction.
*/
#[test]
fn test_add_mod_q_0() {
    let mut a = BigInt::from_slice(&[2, 1, 0, 0]);
    let mut b = BigInt::from_slice(&[0, 1, 0, 0]);

    // This modulus should trigger reduction.
    // Subtracting p is easy, and doesn't require using any borrow
    let p = BigInt::from_slice(&[1, 2, 1, 2]);

    let c = a.add_mod(b, p);

    assert_equal(c.limbs, [2, 2, 0, 0].as_slice(), 4);
}


/*
Function: get_qc_mult

Testcase: a*b= ([0,20]*[0,10]), p=[0,4]. 
This should return q=[0,50], c=0 (c is currently expressed in 2 limbs)
*/
// #[test]
fn test_get_qc_mult_simple_division2() {
    // a = 20 * 2^120
    let a = BigInt::from_slice(&[0, 20]);
    // b = 10 * 2^120
    let b = BigInt::from_slice(&[0, 10]);
    // p = 4 * 2^120
    let p = BigInt::from_slice(&[0, 4]);

    // a*b = 20 * 2^120 * 10 * 2ˆ120, q = [0,50], c = 0
    let (q, c) = get_qc_mult(a, 2, b, 2, p);

    assert_equal(q.limbs, [0, 50].as_slice(), q.limbs.len() as u32);
    // TODO this could have just 1 limb
    assert_equal(c.limbs, [0, 0].as_slice(), c.limbs.len() as u32);
}

/*
Function: get_qc_mult

Testcase: a*b= ([0,20]*[10]), p=[0,4]. 
This should return q=[50], c=0 (c is currently expressed in 2 limbs)
*/
// TODO uncomment when get_qc_mult can be run with variable lengths
// #[test]
fn test_get_qc_mult_simple_division3() {
    // a = 20 * 2^120
    let a = BigInt::from_slice(&[0, 20]);
    // b = 10
    let b = BigInt::from_slice(&[10]);
    // p = 4 * 2^120
    let p = BigInt::from_slice(&[0, 4]);

    // a*b = 200 * 2ˆ120, q = 50, c = 0
    let (q, c) = get_qc_mult(a, 2, b, 1, p);

    assert_equal(q.limbs, [50].as_slice(), q.limbs.len() as u32);
    // TODO this could have just 1 limb
    assert_equal(c.limbs, [0,0].as_slice(), c.limbs.len() as u32);
}

// #[test]
fn test_bn254fr() {
    // Bn254Fr::from_le_bytes_32(
    let mut nr1_arr = [
        51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ];
    // nr1_arr[0]=10;
    let mut nr2_arr = [
        51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ];
    // nr2_arr[0]=2;
    let nr1 = Bn254Fr::from_le_bytes_32(nr1_arr);
    let nr2 = Bn254Fr::from_le_bytes_32(nr2_arr);

    println(nr1 / nr2);
    let b: U128 = to_U128(1329227995784915872903807060280344576);
    // b = floor(b/(v_{n-1}+1))
    // v_{n-1} is the most significant limb of p
    // division should be done in the integer, not in the field
    let temp: U128 = to_U128(5);
    // This does division with floor
    let d_u128: U128 = b / temp;
    let d: Field = d_u128.to_integer();
    let d4 = Bn254Fr::from_le_bytes_32((4 * d).to_le_bytes(32).as_array());
    println(d4 / (nr1 + nr1 + nr1));
    println(nr1 / d4);
}

// Note: the other tests pass.
#[test]
fn test_get_qc_mult_simple_division4() {
    // a = 20 * 2^120 + 2^240
    // 1766847064778384329583297500742918542412043812573936416197747406899511296
    let a = BigInt::from_slice(&[0, 20, 1]);
    // b = 10 * 2^120 + 2^240
    // 1766847064778384329583297500742918529119763854724777687159676804096065536
    let b = BigInt::from_slice(&[0, 10, 1]);
    // equals [0, 0, 200, 30, 1]
    // 200 * 2^240 + 30 * 2^360 + 2^480
    // 3121748550315992231381597229793166376204875625879967987543574863305482913459655043046768140941721265709800850056439301930209551543589634788294656
    // Checked with PariGP
    // (20 * 2^120 + 2^240) * (10 * 2^120 + 2^240) == (200 * 2^240 + 30 * 2^360 + 2^480)

    // p = 4 * 2^120
    let p = BigInt::from_slice(&[0, 4]);

    let (q, c) = get_qc_mult(a, 3, b, 3, p);

    println("test result");
    println("q length");
    println(q.limbs.len());
    
    /*
    q should be 
    587135645693458306972370149197334270095273623064962439551553998454941191446181126678860580698591699469860864
    
    in radix-60
    [0,0,50,576460752303423488,7,288230376151711744]
    in hex
    [0,0,0x32,0x800000000000000,0x07,0x400000000000000]

    in radix-120
    [0,50+2^60* 576460752303423488,7+2^60* 288230376151711744]
    [0, 664613997892457936451903530140172338, 332306998946228968225951765070086151]
    664613997892457936451903530140172338 * 2^120 + 332306998946228968225951765070086151* 2^240

    term 2ˆ300 is 288230376151711744 = 400000000000000
    term 2^240 is 7
    term 2^180 is 576460752303423488
    term 2^120 is 50
    term 2^60 is 0
    term 1 is 0
    */
    print_bigint(q, 8);
    assert(q.limbs.slice[0] == 0x00);
    assert(q.limbs.slice[1] == 0x00);
    assert(q.limbs.slice[2] == 0x32);
    assert(q.limbs.slice[3] == 0x0800000000000000);
    assert(q.limbs.slice[4] == 0x07);
    assert(q.limbs.slice[5] == 0x0400000000000000);
    
    assert(c.limbs.slice[0] == 0x00);

}

// TODO add test that specifically hits q being off by 2

#[test]
fn test_reduce_limbs_128_simple() {
    let mut a = BigInt::from_slice(&[0x1234567890abcdef661234567890abcdef1234567890abcdef]);
    let reduced = reduce_limbs_128(&mut a, 1);
    assert_equal(
        reduced.limbs,
        [0x1234567890abcdef1234567890abcdef, 0x1234567890abcdef66].as_slice(),
        2
    );
}

/*
Function: get_qc_add

Testcase: a+b < p
*/
#[test]
fn test_get_qc_add_no_reduction() {
    let mut a = BigInt::from_slice(&[1, 2, 3, 4]);
    let mut b = BigInt::from_slice(&[5, 6, 7, 8]);
    // This modulus is large, and won't trigger reduction mod p
    let p = BigInt::from_slice(&[100, 100, 100, 100]);

    let (q, c) = get_qc_add(a, b, p);

    assert_equal(c.limbs, [6, 8, 10, 12].as_slice(), 4);
    assert(q == 0);
}

/*
Function: get_qc_add

Testcase: 
- a+b > p
- subtracting p is easy, i.e doesn't require borrowing
*/
#[test]
fn test_get_qc_add_with_reduction() {
    let mut a = BigInt::from_slice(&[1, 2, 3, 4]);
    let mut b = BigInt::from_slice(&[5, 6, 7, 8]);

    // This modulus should trigger reduction.
    // Subtracting p is easy, and doesn't require using any borrow
    let p = BigInt::from_slice(&[0, 0, 0, 9]);

    let (q, c) = get_qc_add(a, b, p);

    assert_equal(c.limbs, [6, 8, 10, 3].as_slice(), 4);
    assert(q == 1);
}

/*
Function: get_qc_add

Testcase: 
- a+b > p
- to subtract p, for one index 1 must be borrowed from previous index
(borrow 1 from index 3 for index 2)
*/
#[test]
fn test_get_qc_add_with_reduction_and_borrow() {
    let mut a = BigInt::from_slice(&[1, 2, 0, 4]);
    let mut b = BigInt::from_slice(&[5, 6, 0, 8]);

    // This modulus should trigger reduction. 
    // Subtracting p will require a borrow for index 2
    let p = BigInt::from_slice(&[0, 0, 1, 9]);

    let (q, c) = get_qc_add(a, b, p);

    assert_equal(
        c.limbs,
        [6, 8, 0xffffffffffffffffffffffffffffff, 2].as_slice(),
        4
    );
    assert(q == 1);
}

/*
Function: get_qc_add

Testcase: 
- a+b > p
- to subtract p a borrow from "distance" must be done:
index 2 borrows from index 3
index 0 borrows from index 2
*/
#[test]
fn test_get_qc_add_with_reduction_and_borrow2() {
    let mut a = BigInt::from_slice(&[0, 0, 0, 4]);
    let mut b = BigInt::from_slice(&[0, 0, 0, 8]);
    // Addition: [0,0,0,12]
    let p = BigInt::from_slice(&[1, 0, 1, 9]);
    // Reduction mod p will go as follows:
    // minus [0,0,0,9]
    // 0,0,0,3
    // equals:
    // 0,0,2^120,2
    // minus [0,0,1,0]
    // 0,0,2^120 - 1,2
    // equals:
    // 0,2^120,2^120-2,2
    // equals:
    // 2^120,2^120-1,2^120-2,2
    // minus [1,0,0,0]
    // 2^120-1,2^120-1,2^120-2,2
    // 2^120-1 equals 0xffffffffffffffffffffffffffffff
    // 2^120-2 equals 0xfffffffffffffffffffffffffffffe

    let (q, c) = get_qc_add(a, b, p);
    assert_equal(
        c.limbs,
        [
        0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff, 0xfffffffffffffffffffffffffffffe, 2
    ].as_slice(),
        4
    );
    assert(q == 1);
}

// TODO add schoolbook_mult_no_reduction testcases with different lengths a & b

/*
Function: schoolbook_mult_no_reduction

Testcase: 
- 4 small limbs
- 2 limbs of 2^120-1
- 30 limbs of 2^120-1
*/
#[test]
fn test_schoolbook_mult() {
    // Case 1: 4 small limbs
    let a1 = BigInt::from_slice(&[1, 2, 3, 4]);
    let b1 = BigInt::from_slice(&[5, 6, 7, 8]);
    let c1 = schoolbook_mult_no_reduction(a1, b1);

    assert_equal(c1.limbs, [5, 16, 34, 60, 61, 52, 32].as_slice(), 7);

    // Case 2: 2 limbs of the max value
    let a2 = BigInt::from_slice(&[0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff]);
    let b2 = BigInt::from_slice(&[0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff]);
    let c2 = schoolbook_mult_no_reduction(a2, b2);
    // 2^120-1, 2^120-1
    // 2^120-1 + 2^120-1 * 2^120 = 1766847064778384329583297500742918515827483896875618958121606201292619775

    /*
    Expected outcome (decimal representation):
    3121748550315992231381597229793166305748598142664971150859156959625371735286071490563537443896896969673989899466438829144210059436075882721050625

    If limbs are (hex representation, as printed by Noir):
    0xfffffffffffffffffffffffffffffe000000000000000000000000000001
    0x01fffffffffffffffffffffffffffffc000000000000000000000000000002
    0xfffffffffffffffffffffffffffffe000000000000000000000000000001
    That sums up to:
    1766847064778384329583297500742918513169027905305787212313992080731930625 + 3533694129556768659166595001485837026338055810611574424627984161463861250 * 2^120 + 1766847064778384329583297500742918513169027905305787212313992080731930625* 2^240
    = 3121748550315992231381597229793166305748598142664971150859156959625371735286071490563537443896896969673989899466438829144210059436075882721050625
    Correct
    */
    assert_equal(
        c2.limbs,
        [
        0xfffffffffffffffffffffffffffffe000000000000000000000000000001, 0x01fffffffffffffffffffffffffffffc000000000000000000000000000002, 0xfffffffffffffffffffffffffffffe000000000000000000000000000001
    ].as_slice(),
        3
    );

    // Case 3: 30 limbs of the max value
    let mut a3_limbs = Vec::new();
    let mut b3_limbs = Vec::new();
    for _ in 0..30 {
        a3_limbs.push(0xffffffffffffffffffffffffffffff);
        b3_limbs.push(0xffffffffffffffffffffffffffffff);
    }
    let a3 = BigInt { limbs: a3_limbs };
    let b3 = BigInt { limbs: b3_limbs };
    let c3 = schoolbook_mult_no_reduction(a3, b3);

    assert_equal(
        c3.limbs,
        [
        0xfffffffffffffffffffffffffffffe000000000000000000000000000001,
        0x01fffffffffffffffffffffffffffffc000000000000000000000000000002,
        0x02fffffffffffffffffffffffffffffa000000000000000000000000000003,
        0x03fffffffffffffffffffffffffffff8000000000000000000000000000004,
        0x04fffffffffffffffffffffffffffff6000000000000000000000000000005,
        0x05fffffffffffffffffffffffffffff4000000000000000000000000000006,
        0x06fffffffffffffffffffffffffffff2000000000000000000000000000007,
        0x07fffffffffffffffffffffffffffff0000000000000000000000000000008,
        0x08ffffffffffffffffffffffffffffee000000000000000000000000000009,
        0x09ffffffffffffffffffffffffffffec00000000000000000000000000000a,
        0x0affffffffffffffffffffffffffffea00000000000000000000000000000b,
        0x0bffffffffffffffffffffffffffffe800000000000000000000000000000c,
        0x0cffffffffffffffffffffffffffffe600000000000000000000000000000d,
        0x0dffffffffffffffffffffffffffffe400000000000000000000000000000e,
        0x0effffffffffffffffffffffffffffe200000000000000000000000000000f,
        0x0fffffffffffffffffffffffffffffe0000000000000000000000000000010,
        0x10ffffffffffffffffffffffffffffde000000000000000000000000000011,
        0x11ffffffffffffffffffffffffffffdc000000000000000000000000000012,
        0x12ffffffffffffffffffffffffffffda000000000000000000000000000013,
        0x13ffffffffffffffffffffffffffffd8000000000000000000000000000014,
        0x14ffffffffffffffffffffffffffffd6000000000000000000000000000015,
        0x15ffffffffffffffffffffffffffffd4000000000000000000000000000016,
        0x16ffffffffffffffffffffffffffffd2000000000000000000000000000017,
        0x17ffffffffffffffffffffffffffffd0000000000000000000000000000018,
        0x18ffffffffffffffffffffffffffffce000000000000000000000000000019,
        0x19ffffffffffffffffffffffffffffcc00000000000000000000000000001a,
        0x1affffffffffffffffffffffffffffca00000000000000000000000000001b,
        0x1bffffffffffffffffffffffffffffc800000000000000000000000000001c,
        0x1cffffffffffffffffffffffffffffc600000000000000000000000000001d,
        0x1dffffffffffffffffffffffffffffc400000000000000000000000000001e,
        0x1cffffffffffffffffffffffffffffc600000000000000000000000000001d,
        0x1bffffffffffffffffffffffffffffc800000000000000000000000000001c,
        0x1affffffffffffffffffffffffffffca00000000000000000000000000001b,
        0x19ffffffffffffffffffffffffffffcc00000000000000000000000000001a,
        0x18ffffffffffffffffffffffffffffce000000000000000000000000000019,
        0x17ffffffffffffffffffffffffffffd0000000000000000000000000000018,
        0x16ffffffffffffffffffffffffffffd2000000000000000000000000000017,
        0x15ffffffffffffffffffffffffffffd4000000000000000000000000000016,
        0x14ffffffffffffffffffffffffffffd6000000000000000000000000000015,
        0x13ffffffffffffffffffffffffffffd8000000000000000000000000000014,
        0x12ffffffffffffffffffffffffffffda000000000000000000000000000013,
        0x11ffffffffffffffffffffffffffffdc000000000000000000000000000012,
        0x10ffffffffffffffffffffffffffffde000000000000000000000000000011,
        0x0fffffffffffffffffffffffffffffe0000000000000000000000000000010,
        0x0effffffffffffffffffffffffffffe200000000000000000000000000000f,
        0x0dffffffffffffffffffffffffffffe400000000000000000000000000000e,
        0x0cffffffffffffffffffffffffffffe600000000000000000000000000000d,
        0x0bffffffffffffffffffffffffffffe800000000000000000000000000000c,
        0x0affffffffffffffffffffffffffffea00000000000000000000000000000b,
        0x09ffffffffffffffffffffffffffffec00000000000000000000000000000a,
        0x08ffffffffffffffffffffffffffffee000000000000000000000000000009,
        0x07fffffffffffffffffffffffffffff0000000000000000000000000000008,
        0x06fffffffffffffffffffffffffffff2000000000000000000000000000007,
        0x05fffffffffffffffffffffffffffff4000000000000000000000000000006,
        0x04fffffffffffffffffffffffffffff6000000000000000000000000000005,
        0x03fffffffffffffffffffffffffffff8000000000000000000000000000004,
        0x02fffffffffffffffffffffffffffffa000000000000000000000000000003,
        0x01fffffffffffffffffffffffffffffc000000000000000000000000000002,
        0xfffffffffffffffffffffffffffffe000000000000000000000000000001
    ].as_slice(),
        59
    );
    // TODO add more testcases
}
