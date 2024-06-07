use dep::std::uint128::U128;

// BigInt arithmetic

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
    // Initialize vector for the same length
    let mut reduced_limbs: Vec<Field> = Vec::new();
    for _ in 0..a.limbs.len() {
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
    for j in 0..a.limbs.len() {
        let i = a.limbs.len() - 1 - j;

        if !stop_subtracting { // Workaround for not being able to break out of loop
            // Check p[i] > res[i]
            if gt(p.limbs.get(i), res_limbs.get(i)) {
                // If this is the highest limb, we immediately know p cannot be subtracted
                // and break the loop
                if i == a.limbs.len() - 1 {
                    stop_subtracting = true; // work around instead of break
                } else {
                    let mut already_borrowed = false;
                    // Start looking for the next non-zero entry that can give a borrow
                    for k in (i + 1)..a.limbs.len() {
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
                                reduced_limbs.slice[i] = 1329227995784915872903807060280344576 + res_limbs.get(i)-p.limbs.get(i);
                                already_borrowed = true;
                            }
                        }
                    }
                    stop_subtracting = !already_borrowed;
                }
            } else {
                // If p[i] <= res[i], we have easy subtraction: res[i] - p[i]
                reduced_limbs.slice[i] = res_limbs.get(i) - p.limbs.get(i);
            }
        }
    }

    // 3. If p was subtracted, return (q=0, a+b). Else return (q=1, a+b-p)

    // To find out whether p was subtracted, we compare res_limbs and reduced_limbs
    // If they are different, p might have been subtracted.
    let mut limbs_different = false;
    // Once again, this requires the limbs to have max 128 bits
    for i in 0..a.limbs.len() {
        if !limbs_different { // workaround instead of break
            if neq(reduced_limbs.get(i), res_limbs.get(i)) {
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

// TODO place these helper functions in utils / somewhere

// Returns the field cast to U128
// assymed field has <= 128 bits
fn to_U128(f: Field) -> U128 {
    let f_le_bytes: [u8;16] = f.to_le_bytes(16).as_array();
    U128::from_le_bytes(f_le_bytes)
}

// Returns f1 > f2, when intrepreting the fields as uints
// assumes fields have <= 128 bits
fn gt(f1: Field, f2: Field) -> bool {
    // Convert both fields to U128 and compare
    to_U128(f1) > to_U128(f2)
}

// Returns f1 != f2, when intrepreting the fields as uints
// assumes fields have <= 128 bits
fn neq(f1: Field, f2: Field) -> bool {
    // Convert both fields to U128 and compare
    to_U128(f1) != to_U128(f2)
}

/*
Function: get_qc_add

Testcase: a+b < p
*/
#[test]
fn test_get_qc_add_no_reduction() {
    let a = BigInt::from_slice(&[1, 2, 3, 4]);
    let b = BigInt::from_slice(&[5, 6, 7, 8]);
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
    let a = BigInt::from_slice(&[1, 2, 3, 4]);
    let b = BigInt::from_slice(&[5, 6, 7, 8]);

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
    let a = BigInt::from_slice(&[1, 2, 0, 4]);
    let b = BigInt::from_slice(&[5, 6, 0, 8]);

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
    let a = BigInt::from_slice(&[0, 0, 0, 4]);
    let b = BigInt::from_slice(&[0, 0, 0, 8]);
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
    Expected outcome:
    3121748550315992231381597229793166305748598142664971150859156959625371735286071490563537443896896969673989899466438829144210059436075882721050625

    If limbs are:
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

// Test helpers
// TODO move to test helpers file / somewhere

fn assert_equal(a: Vec<Field>, b: [Field], len: u32) {
    assert(a.len() == b.len());
    for i in 0..len {
        assert(a.get(i as u64) == b[i]);
    }
}

fn print_bigint(a: BigInt, len: u64) {
    for i in 0..len {
        println(a.limbs.get(i))
    }
}
