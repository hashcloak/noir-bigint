# Noir BigInt over arbitrary moduli

We present **noir-bigint**, a library that implements modular arithmetic between big-integers using a big-integer modulus. Concretely, this library allows the developer to compute $a \odot b = c \mod p$, where $\odot \in \{+, -, *, / \}$ and $p \in \mathbb{Z}$ is a prime modulus. The library represents all the big-integers as an array of $N$ limbs, were $N$ is an positive integer defined at compile time. The only restriction that the library offers is that $N$ should be less than 64, which is a reasonable assumption for most of the real-world applications.

## `BigNum` struct

The `BigNum` struct is the base struct that represent a big-integer where each limb is represented using 120 bits. The representation works by storing the limbs in a fixed length array of size $N$, where $N$ is defined at compile-time.

### Functions

- `new() -> Self`: creates a new `BigNum` instance representing the number zero.
- `one() -> Self`: creates a new `BigNum` instance representing the number one.
- `from_byte_be<NBytes>(x: [u8; NBytes]) -> Self`: takes an array of bytes in big endian format. In the representation, each 120-bit limb is represented using 15 bytes. We also require that the size of the byte array is long enough to to cover the amount of bits in the modulus.
- `validate_in_range(self)`: checks if each limb of `self` can be represented in 120 bits. Also we check that the number is less than $2^{\lceil \log_2 p \rceil}$. This is a lazy check to obtain a better performance that is done instead of checking that `self` is less than $p$.
- `assert_is_not_equal(self, other: Self)`: checks if $a = b \mod N$. This method is sound but not complete. It may happen that $a \neq b$ but $a = b \mod N$, however the probability that this occurs is small.
- `validate_quotient_in_range(self)`: validates that the quotient produced from `evaluate_quadratic_expression()`. This validation consists in checking that each limb has 120 bits and that the last limb has the same number of bits that the las limb of the modulus $p$ plus 6. This 6 comes from the fact that we allow multiplications of numbers with at most 64 limbs.
- `validate_in_field(self: Self)`: validate that `self` is in the field $\mathbb{Z}_p$ where $p$ is the modulus parameter.
- `conditional_select(self: Self, other: Self, predicate: bool)`: given the value in the `predicate` return either `self` if `predicate` is zero or `other` if `predicate` is 1. 
- `evaluate_quadratic_expression<LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(lhs_products: [[BNExpressionInput<N, Params>; LHS_N]; NUM_PRODUCTS], rhs_products: [[BNExpressionInput<N, Params>; RHS_N]; NUM_PRODUCTS], linear_terms: [BNExpressionInput<N, Params>; ADD_N])`: constrains to the following quadratic expression:
    $$
    \sum_{i=0}^{N_P - 1} \left(\sum_{j=0}^{N_L-1} L[i][j] \cdot \sum_{j=0}^{N_R-1} R[i][j] \right) + \sum_{i=0}^{N_A - 1} A[i] = q \cdot p
    $$.
    The function receives the right-hand side products, the left-hand side products, and the linear terms, and the function computes the appropriate $q$ such that the constrain in the previous equation is fulfilled. This function is particularly useful when we need to constrain multiple products by expressing the constrain as a quadratic expression and check them in one run.


### Trait implementations

The `BigNum<N, Params>` struct implements the following arithmetic traits
- `std::ops::Add`
- `std::ops::Sub`
- `std::ops::Mul`
- `std::ops::Div`

Therefore, through our library, developers can obtain $a \odot b = c \mod p$ where $\odot \in \{+, -, *, / \}$ with the corresponding overloaded operators from the Rust programming language.

Also, the `BigNum<N, Params>` implements the `std::cmp::Eq` trait. With this trait, you can tell wether two `BigNum` instances are equal limb by limb.

### Configuring parameters for `BigNum`

To be able to use the `BigNum` struct, we need to define first the parameters that will be used to compute arithmetic operations. The list of parameters that need to be defined are:
- The modulus $p$: this parameter should be specified as an array of field elements. This array consist of the limbs of the modulus in a 120-bit `Field` elements.
- Double modulus $2p$: this parameter is the modulus $p$ of the previous described parameter multiplied by two. Having this parameter from the beginning optimizes the computation of $2p$ which is needed in some functions. This double modulus is specified also as an array of 120-bit `Field` elements that represent the limbs of the value.
- The number of bits of the modulus.
- The algorithm that will be used to multiply two elements. Here we have two choices, using schoolbook multiplication, or one of the fix-length karatsuba multiplication algorithms.
- The Barret reduction parameters:
    - the reduction parameter
    - $k$

To set this parameters, we defined the trait `BigNumParamsTrait` which define functions to access each of the parameters. The developer must define a struct that implement those parameters and implement the corresponding functions that we show next:

```rust
trait BigNumParamsTrait<N> {
    fn modulus() -> [Field; N];
    fn double_modulus() -> [Field; N];
    fn redc_param() -> [Field; N];
    fn k() -> u64;
    fn modulus_bits() -> u64;
    fn mult(a: [Field; N], b: [Field; N]) -> ArrayX<Field, N, 2>;
}
```
In the library, you may find some implementations of the `BigNumParamsTrait` in the folder `src/fields/` as an example. 