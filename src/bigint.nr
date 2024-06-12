use crate::utils::{gt, lt, to_U128};
use crate::test_utils::{assert_equal, print_bigint};
use dep::std::field::bn254::decompose;

// BigInt arithmetic

// Number of bits for each limb. With respect to Noir implementation, this
// represents d.
global LIMB_BITS: Field = 120;
// The maximum value for a limb is 2^120
global MAX_VALUE_LIMB: Field = 0x100000000000000000000000000000000000000000000000000000000000000000000000000;

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
If a and b have n limbs, the result will have 2n-1 limbs. 

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
    assert(a.limbs.len() == b.limbs.len());

    let n = a.limbs.len();
    let mut res_limbs = Vec::new();
    for _ in 0..2 * n - 1 {
        res_limbs.push(0);
    }
    for i in 0..n {
        for j in 0..n {
            res_limbs.slice[i+j] += a.limbs.get(i)*b.limbs.get(j);
        }
    }

    BigInt { limbs: res_limbs }
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
    
    // a*b can have limbs larger than 120 bits
    // for next steps, the limbs need to fit in U128
    // so reduce limbs to 128 bits
    u = reduce_limbs_128(&mut u, len_a+len_b-1);

    assert(u.limbs.len() == (len_a+len_b-1));
    let len_u = len_a+len_b-1;

    // If u is shorter than p, we can conclude q = 0 and c = a*b
    if (u.limbs.len() < p.limbs.len()) {
        (BigInt::zero(), u)
    }

    println("u limbs len");
    println(u.limbs.len());
    for i in 0..3 {
        println(u.limbs.slice[i]);
        /*
      0xc8
      0x1e
      0x01
      */
    }
    // We assume p is already in reduced limbs form

    let n = p.limbs.len();
    // TODO does the algorithm support m = 0?
    // why yes / no?
    // TODO fix m
    let m = len_u - n; //u.limbs.len() - n; // Difference in length
    
    let mut q_vec = Vec::new();
    for _ in 0..m + 1 {
        q_vec.push(0);
    }

    // Start Division algorithm
    // Following the algorithm, v = p.
    // D1

    // b = 2^120
    // Can't write this as 1 << 120 because it doesn't fit in a u64.
    let b: U128 = to_U128(1329227995784915872903807060280344576);
    // b = floor(b/(v_{n-1}+1))
    // v_{n-1} is the most significant limb of p
    // division should be done in the integer, not in the field
    let temp: U128 = to_U128(p.limbs.get(p.limbs.len() - 1) + 1);
    // This does division with floor
    let d: U128 = b / temp;

    for i in 0..len_u {
        u.limbs.slice[i] = (to_U128(u.limbs.slice[i]) * d).to_integer();
    }
    let len_before = u.limbs.len();
    u = reduce_limbs_128(&mut u, len_u);
    let len_after = u.limbs.len();
    // We need an extra digit so u becomes of length m+n
    if len_after == len_before {
        println("Add additional 0");
        u.limbs.insert(len_u, 0);
    }
    println("new u length");
    println(u.limbs.len());

    let mut p_limbs: Vec<Field> = Vec::new();
    for i in 0..p.limbs.len() {
      p_limbs.push((to_U128(p.limbs.slice[i])*d).to_integer());
    }

    // D2
    // This is safe because we checked length above
    let mut j = m; //u.limbs.len() - p.limbs.len();

    // Workaround for reverse loop
    // The result is [q_0,q_1..q_{m}]
    for _ in 0..m + 1 {
        println("j");
        println(j);

        // D3
        let mut index_1 = n + j;
        println("index_1");
        println(index_1);
        let temp1 = to_U128(u.limbs.get(index_1) + u.limbs.get(index_1 - 1));
        // U128 has division and modulo operations
        // this is why u needs to have reduced limbs
        let mut q_head: U128 = temp1 / to_U128(p_limbs.get(n - 1));
        let mut r_head: U128 = temp1 % to_U128(p_limbs.get(n - 1));
        println(q_head);
        println(r_head);

        // Note: q_head is never more than 2 in error.
        // Only perform this check if it doesn't trigger out of bound:
        let mut check2 = false;
        if n >= 2 & index_1 >= 2 {
            let temp2 = q_head * to_U128(p_limbs.get(n - 2));
            let temp3 = b * r_head + to_U128(u.limbs.get(index_1 - 2));
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
                    let temp3 = b * r_head + to_U128(u.limbs.get(index_1 - 2));
                    check2 = temp2 > temp3;
                }
                // let temp2 = q_head * to_U128(p.limbs.get(n - 2));
                // let temp3 = b * r_head + to_U128(u.limbs.get(index_1 - 2));
                if q_head >= b | check2 {
                    // TODO make this checked_sub
                    q_head -= to_U128(1);
                    r_head += to_U128(p.limbs.get(n - 1));
                }
            }
        }

        println(q_head);

        // D4
        // Get [u_j,..,u_{j+n}]
        let mut u_j_limbs = Vec::new();
        for i in 0..n + 1 {
            u_j_limbs.push(u.limbs.get(j + i));
        }
        // Calculate [u_j,..,u_{j+n}] - q_head * [p_0,p_1,..,p_{n-1},0]
        // limbs of p have max 120 bits, so multiplication with q_head will fit with Field
        let mut q_head_p_limbs = Vec::new();
        for i in 0..n {
            q_head_p_limbs.push((to_U128(p_limbs.get(i)) * q_head).to_integer());
        }
        q_head_p_limbs.push(0);

        // Returns the updated limbs  
        let (res_limbs_segment, underflow) = sub_reduced_limbs(u_j_limbs, q_head_p_limbs);

        println(res_limbs_segment.slice[0]);
        println(res_limbs_segment.slice[1]);

        if underflow {
            // TODO 
            // D6
            println(100);
        }

        // Set the updated limbs to the correct segment of u
        for i in 0..n {
            u.limbs.slice[j+i] = res_limbs_segment.slice[i];
        }

        // D5
        q_vec.slice[j] = q_head.to_integer();

        // D7
        j -= 1;
    }

    // D8
    // quotient [q_0,q_1,..,q_m]
    // remainder [u_0,u_1,..,u_{n-1}] / d

    // TODO check for highest limbs being zero?
    let res_q = BigInt { limbs: q_vec };

    let mut r_vec = Vec::new();
    for i in 0..n {
        r_vec.push((to_U128(u.limbs.slice[i]) / d).to_integer());
    }
    let res_r = BigInt { limbs: r_vec };

    (res_q, res_r)
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


#[test]
fn test_get_qc_mult_simple_division() {
    // a = 20 + 2^120
    // array_to_number([20,1])
    // 1329227995784915872903807060280344596
    let a = BigInt::from_slice(&[20, 1]);
    // b = 10 + 2^120
    // array_to_number([10,1])
    // 1329227995784915872903807060280344586
    let b = BigInt::from_slice(&[10, 1]);
    let p = BigInt::from_slice(&[4]);


    // a*b = 
    // 1766847064778384329583297500742918555704323770423095145235818009702957256
    let (q, c) = get_qc_mult(a, 2, b, 2, p);

    println("test result");
    println("q length");
    println(q.limbs.len());
    print_bigint(q, 3);
    println("c length");
    println(c.limbs.len());
    print_bigint(c, 1);
    /*
    Expected q = 441711766194596082395824375185729638926080942605773786308954502425739314
    [664613997892457936451903530140172338, 332306998946228968225951765070086151]
    r = 0
    */
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
