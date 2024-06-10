// Utils for the implementation of the BigUint library.

// Returns the field cast to U128
// assymed field has <= 128 bits
pub fn to_U128(f: Field) -> U128 {
    let f_le_bytes: [u8;16] = f.to_le_bytes(16).as_array();
    U128::from_le_bytes(f_le_bytes)
}

// Returns f1 > f2 where f1 and f2 two field elements by interpreting the fields
// as uints. The function assumes that field elements have <= 128 bits.
pub fn gt(f1: Field, f2: Field) -> bool {
    // Convert both fields to U128 and compare
    to_U128(f1) > to_U128(f2)
}

// Returns f1 > f2 where f1 and f2 two field elements by interpreting the fields
// as uints. The function assumes that field elements have <= 128 bits.
pub fn lt(f1: Field, f2: Field) -> bool {
    // Convert both fields to U128 and compare
    to_U128(f1) < to_U128(f2)
}

// Returns x mod d where x and d are in an intger field like Z_p for some prime
// p.
pub fn mod_field(x: Field, d: Field) -> Field {
    if x.lt(d) { x } else { d - x }
}
