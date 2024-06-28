# How to create BigNumParamsTrait for my modulus

To start working with bigints, you need to implement the BigNumParamsTrait. It has the following methods:

```
trait BigNumParamsTrait<N> {

    fn modulus() -> [Field; N];

    fn double_modulus() -> [Field; N];

    fn redc_param() -> [Field; N];

    fn k() -> u64;

    fn modulus_bits() -> u64;

    fn mult(a: [Field; N], b: [Field; N]) -> ArrayX<Field, N, 2>;
}
```

## N

`N` is the number of limbs needed to represent the bigint in radix-120, with enough space to represent `2p` and `redc` which is needed for next steps: `ceil(modulus_bits+1 / 120)`. 

## modulus

Return modulus `p` in radix-120 in little-endian. 

## double_modulus

Return `2p` in radix-120 in little-endian.

// TODO what if needs a new limb? For example when we have 3000 bits, it fits exactly in 25 limbs and 2p overflows.

## redc_param, k

These parameters are used for Barrett reduction: `redc = floor(2^2k / p)` for `k = modulus_bits` or `k = modulus_bits+1`.

## modulus_bits

Return the number of bits `p` has. 

## mult

Call the most efficient multiplication algorithm for this length (either schoolbook or Karatsuba multiplication).