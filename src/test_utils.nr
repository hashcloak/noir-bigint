use crate::bigint::BigInt;

// Asserts if the array a has has the same elements as the slice b. Both arrays
// should have the same length len.
pub fn assert_equal(a: Vec<Field>, b: [Field], len: u32) {
    assert(a.len() == b.len());
    for i in 0..len {
        assert(a.get(i as u64) == b[i]);
    }
}

// Utility to print a BigInt with len limbs.
pub fn print_bigint(a: BigInt, len: u64) {
    for i in 0..len {
        println(a.limbs.get(i))
    }
}
