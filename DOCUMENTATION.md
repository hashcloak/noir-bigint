# Noir BigInt documentation

`noir-bigint` is a library that implements big-integers in Noir as a utility to develop other cryptographic primitives and tools for the Noir ecosystem. In this document, you will find all the documentation related with the implementation of the mentioned library from both theoretical and practical perspective.

## The goal

The goal is to implement a library that evaluates operations modulo an integer $p$ so that both the operands and the modulus can have arbitrary bit lengths. We will represent the operands and the modulus as $l$-bit big-integers. Each number will be defined as an array of $d$-bit *limbs*. Therefore, each value will need $N = \lceil\frac{l}{d}\rceil$ limbs for its representation.

Once the representation is defined, we want to expose an API that allows developers to write modular arithmetic zero-knowledge proofs using this big-integer modulus representation. Concretely, given $c \in \mathbb{Z}_p$, a prover wants to prove that he knows $a, b \in \mathbb{Z}_p$, such that $c$ is the sum or the product of $a$ and $b$ modulo $p$. This modular arithmetic is relevant in other cryptographic constructions like RSA signature schemes.

In the context of ZK-proofs, choosing $d$ is an important task, given that it will affect the efficiency of the proof generation. The algorithms considered in the library require approximately $O(N^{1.5})$ multiplications and additions and $O(l)$ range checks. As we mentioned before, $d$ is inversely proportional to $N$. Hence, a large $d$ would be a good choice for a large modulus. However, if the modulus is small, it is best to choose a small $d$ to reduce the complexity of the algorithms.

In the rest of the document and the implementation, we will consider $d = 120$ as a reasonable choice of parameters. Also, in the implementation, we consider $N$ to be fixed because of the technical limitations of Noir, as the library does not support an efficient mechanism to store the limbs dynamically. Although the library support Rust-like vectors, they are not very efficient and pur goal is also to implement something that can be used in production. Hence, we are limited to using fixed-length arrays to represent the collection of limbs for a number. To give more freedom during circuit development, the API is designed so that the programmer can set the value of $N$ at compile time.

## Big-integer representation

The building block to construct a big-integer library is the BigNum struct:

```rust
struct BigNum<N,Params> {
    limbs: [Field; N],
}
```

This struct represents a big-integer with $N$ limbs. Each limb will be represented as a `Field` element whose value is in the range $\{0, \dots, 2^d - 1\}$ (remember that in this case, $d = 120$). We also say that the number is represented in a radix of $d$ bits. Considering this representation, if a number is represented using the vector $(a_0, \dots, a_{N-1})$, then, the decimal representation of this number will be $\sum_{i=0}^{N-1} a_i \cdot 2^{d \cdot i}$.

The API is designed around this struct so the addition and multiplication are defined as methods implemented for this struct.

## Utilities

During the library's implementation, we require some utilities that allow us to implement the arithmetic operations in an idiomatic way. Here, we describe those utilities and their usage inside the main arithmetic algorithms.

### `ArrayX`

The struct `ArrayX` is an implementation of an array whose length is the product of a known multiplier `SizeMultiplier` and $N$. For example, if we define the value of $N$ at compile time and need to store twice that amount of values, we create an `ArrayX` where `SizeMultiplier` is two. This implementation is a workaround to have arrays whose length is $c \cdot N$ for a known constant $c$ because, in our implementation, the value of $N$ is considered a generic, and it is not possible to operate over generics to create an array of size $c \cdot N$.

The struct for `ArrayX` is presented next:

```rust
struct ArrayX<T, N, SizeMultiplier> {
    segments: [[T; N]; SizeMultiplier]
}
```

Notice that `ArrayX` is represented in a matrix fashion. However, it is important to remember that this can be considered an array of length `SizeMultiplier * N`.

This array implementation contains some methods of interest:
- The array implements the functions `set()` and `get()` to modify and retrieve a certain index from the array. The index of the array that is being queried needs to be between 0 and `SizeMultiplier * n - 1`.
- The implementation of the array also has some arithmetic operations like `add_assign()`, `sub_assign()`, and `mul_assign()` that allow to do the arithmetic operations in place. 

One of the main uses of `ArrayX` is to transform a number from a 120-bit radix representation to a 60-bit radix representation. When we transform over a number with $N$ limbs in the 120-bit representation, we obtain a representation in 60-bit radix with $2N$ limbs. Hence, in this case, we consider `SizeMultiplier` equal to two.

### `U60Repr`

The `U60Repr` struct represents a big integer as an array of 60-bit limbs. The main use of this struct is to convert the big integers in the 120-bit limbs into this representation to perform additions and subtraction in a lower number of bits to avoid overflow. This overflow is avoided because the sum of two 60-bit limbs is, at most, 61 bits and can be stored using the `u64` type.

The `U60Repr` struct is defined as an ArrayX of u64 elements:
```rust
struct U60Repr<N, NumSegments> {
    limbs: ArrayX<u64, N, NumSegments>
}
```

There are some methods of interest in this representation:
- `U60Repr` implements the traits `std::ops::Add` and `std::ops::Sub` which allow to the programmer to use the operators `+` and `-` between two `U60Repr`. Those traits are implemented using the schoolbook addition and subtraction in which the operation is performed limb by limb, starting from the least significant limb and storing the carry value for the next limb operation. We suggest reading "The Art of Computer Programming Volume 2" by Donal Knuth in section 4.3 for more information about how the schoolbook addition and subtraction works.
- `U60Repr` implements the trait `std::convert::From<[Field; N]>`, transforming a big-integer number with a 120-bit radix representation into a 60-bit limb representation.
- `U60Repr` implements the trait `std::convert::Into<[Field; N]>` to convert from 60-bit to 120-bit radix representation.

Using the above methods, the strategy consists of taking big integers in the 120-bit representation and converting them into a 60-bit representation. Then, we perform the additions or subtractions in this reduced representation, and we transform the resulting big integer back to the 120-bit representation to continue with the rest of the circuit. It is important to consider that most of the methods of `U60Repr` are executed using unconstrained functions to avoid the overhead that comes from using `u64` data types and comparing them.

## Addition


## Multiplication

### Schoolbook multiplication

### Karatsuba multiplication