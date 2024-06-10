use crate::utils::{gt, lt};
use crate::test_utils::assert_equal;

// BigInt arithmetic

// Number of bits for each limb. With respect to Noir implementation, this
// represents d.
global LIMB_BITS: Field = 120;
global MAX_VALUE_LIMB: Field = 0x100000000000000000000000000000000000000000000000000000000000000000000000000; // The maximum value for a limb is 2^120

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
Function: get_qc_add

Testcase: a+b < p
*/
#[test]
fn test_get_qc_add_no_reduction() {
    let mut a = BigInt::from_slice(&[1, 2, 3, 4]);
    let mut b = BigInt::from_slice(&[5, 6, 7, 8]);
    // This modulus is large, and won't trigger reduction mod p
    let p = BigInt::from_slice(&[100, 100, 100, 100]);

    let (_, c) = get_qc_add(a, b, p);

    assert_equal(c.limbs, [6, 8, 10, 12].as_slice(), 4)
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

    let (_, c) = get_qc_add(a, b, p);

    assert_equal(c.limbs, [6, 8, 10, 3].as_slice(), 4)
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

    let (_, c) = get_qc_add(a, b, p);

    assert_equal(
        c.limbs,
        [6, 8, 0xffffffffffffffffffffffffffffff, 2].as_slice(),
        4
    )
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

    let (_, c) = get_qc_add(a, b, p);
    assert_equal(
        c.limbs,
        [
        0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff, 0xfffffffffffffffffffffffffffffe, 2
    ].as_slice(),
        4
    )
}

// Test helpers
// TODO move to test helpers file / somewhere

