# Noir BigInt documentation

`noir-bigint` is a library that implements big-integers in Noir as a utility to develop other cryptographic primitives and tools for the Noir ecosystem. In this document, you will find all the documentation related with the implementation of the mentioned library from both theoretical and practical perspective.

## The goal

The goal is to implement a library that evaluates operations modulo an integer $p$ so that both the operands and the modulus can have arbitrary bit lengths. We will represent the operands and the modulus as $l$-bit big-integers. Each number will be defined as an array of $d$-bit *limbs*. Therefore, each value will need $N = \lceil\frac{l}{d}\rceil$ limbs for its representation.

Once the representation is defined, we want to expose an API that allows developers to write modular arithmetic zero-knowledge proofs using this big-integer modulus representation. Concretely, given $c \in \mathbb{Z}_p$, a prover wants to prove that they know $a, b \in \mathbb{Z}_p$, such that $c$ is the sum or the product of $a$ and $b$ modulo $p$. This modular arithmetic is relevant in other cryptographic constructions like RSA signature schemes.

The implementation and this documentation follow the ideas presented in the blog post "[Big integer multiplication in Noir over arbitrary moduli](https://hackmd.io/@aztec-network/S1LyK89JC)" by Zachary James Williamson. We encourage the reader to read the blog post to familiarize with the initial ideas. However, much of the design considered in this implementation and documentation has changed significantly over the ideas presented in the blog port.

In the context of ZK-proofs, choosing $d$ is an important task, given that it will affect the efficiency of the proof generation. The algorithms considered in the library require approximately $O(N^{1.5})$ multiplications and additions and $O(l)$ range checks. As we mentioned before, $d$ is inversely proportional to $N$. Hence, a large $d$ would be a good choice for a large modulus. However, if the modulus is small, it is best to choose a small $d$ to reduce the complexity of the algorithms.

In the rest of the document and the implementation, we will consider $d = 120$ as a reasonable choice of parameters. Also, in the implementation, we consider $N$ to be fixed because of the technical limitations of Noir, as the library does not support an efficient mechanism to store the limbs dynamically. Although the library support Rust-like vectors, they are not very efficient and pur goal is also to implement something that can be used in production. Hence, we are limited to using fixed-length arrays to represent the collection of limbs for a number. To give more freedom during circuit development, the API is designed so that the programmer can set the value of $N$ at compile time.

## Big-integer representation

The building block to construct a big-integer library is the BigNum struct:

```rust
struct BigNum<N,Params> {
    limbs: [Field; N],
}
```

This struct represents a big-integer with $N$ limbs. Each limb will be represented as a `Field` element whose value is in the range $\{0, \dots, 2^d - 1\}$ (remember that in this case, $d = 120$). We also say that the number is represented in a radix of $d$ bits. Tipicaly, the `Field` element can store more than $d$-bit numbers, hence we have some free bits in the most significant section of a `Field` to make use of it in case there is an overflow while operating $d$-bit elements. The amount of bits for a `Field` element depends on the backend used to run the proof. For the rest of the discussion, we will assume that the number of bits stored in a `Field` element is 254 wich is the bit length given by the curve in the default backend. Considering this representation, if a number is represented using the vector $(a_0, \dots, a_{N-1})$, then, the decimal representation of this number will be $\sum_{i=0}^{N-1} a_i \cdot 2^{d \cdot i}$.

The API is designed around this struct so the addition and multiplication are defined as methods implemented for this struct.

## Utilities

During the library's implementation, we require some utilities that allow us to implement the arithmetic operations in an idiomatic way. Here, we describe those utilities and their usage inside the main arithmetic algorithms.

### `ArrayX`

The struct `ArrayX` is an implementation of an array whose length is the product of a known multiplier `SizeMultiplier` and $N$. For example, if we define the value of $N$ at compile time and need to store twice that amount of values, we create an `ArrayX` where `SizeMultiplier` is two. This implementation is a workaround to have arrays whose length is $c \cdot N$ for a known constant $c$ because, in our implementation, the value of $N$ is considered a generic, and it is not possible to operate over generics to create an array of size $c \cdot N$.

The struct for `ArrayX` is presented next:

```rust
struct ArrayX<T, let N: u64, let SizeMultiplier: u8> {
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

## Modular arithmetic in ZK

First, let us remind the goal at hand. In the context of ZK-proofs, a prover wants to prove that they know $a, b \in \mathbb{Z}_p$ such that $c = a \odot b \mod p$, for some $c \in \mathbb{Z}_p$, and $\odot \in \{+, \times \}$. The strategy that we will consider in the implmenetation is to compute $q, c \in \mathbb{Z}$ such that $a \odot b = p \cdot q + c$, for $c < p$, using Noir unconstrained functions. The unconstrained functions allow us to compute intermediate witnesses that are not constrained by the proof, and therefore, cheap to compute. Once we have computed $q$ and $c$, we constrain them to the condition $a \odot b - p \cdot q - c = 0$ to prove that $c$ is the reduction modulo $p$ that we are looking for. In the implementation, we do the constraining in a more general way considering not just the case of the addition and multiplication modulo $p$ but for an arbitrary quadratic expression. We will cover this ideas in deep later.

### Constraining quadratic expressions

One of the most important parts of the algorithm is constraining to the condition $a \odot b - p \cdot q - c = 0$, for some $q, c \in \mathbb{Z}$ such that $c < p$. In the implementation, we generalize this check to more general quadratic expressions. Our goal is to constrain the following quadratic expression:

$$
\sum_{i=0}^{N_P - 1} \left(\sum_{j=0}^{N_L-1} L[i][j] \cdot \sum_{j=0}^{N_R-1} R[i][j] \right) + \sum_{i=0}^{N_A - 1} A[i] = q \cdot p
$$.

Here
- $N_P$ is the number of products that will be computed,
- $N_L$ is the number of products in the left hand side,
- $N_R$ is the number of products in the right hand side,
- $N_A$ is the number of linear terms in the expression,
- $L$ is a colection of terms in the left hand side,
- $R$ is a colection of terms in the right hand side, and
- $A$ is the colection of linear terms.

First, the function computes the quotient $q$ of the quadratic expression along with the borrow flags that point when an underflow occurred during the subtractions. The computation of the quotient and the borrow flags will be covered in the next section. Then, the function takes the left hand side $L$ and the right hand side $R$ and computes internal sums. Those sums are accumulated in `t0` and `t1` respectively. The same thing holds for the linear terms in $A$ which is accumulated in `t4`. In the construction of `t0`, `t1` and `t4`, we are subtracting the negative terms but then we add $2N$ to the current result. The reason for this correction with $2N$ is because the big-integers in our implementations are **lazily** constrained. This means that when we create a `BigNum` $a$, we do not check that $a < p$, instead we check that $a < 2^{\lceil \log_2 p \rceil}$. This last comparison is more efficient than the first one in the context of ZK proofs. Therefore, if we have an input $x' = x + p$ for $x \geq 0$, to compute his negative counterpart, we compute $2p - x'$ to obtain a positive number (notice that if we do $p - x'$, we obtain a negative number). At the end, $2p - x' \equiv -x' \mod p$.

After evaluating `t1`, `t2` and `t4`, we compute $t_0 * t_1 + t_4 - q \cdot c$. Here is when we use `ArrayX` as a mechanism to store the limbs. This is because the product of `t1` and `t2` will give us $2N - 1$ limbs. The idea behind this computation is to constrain $t_0 * t_1 + t_4 - q \cdot c = 0$. At this point we are using schoolbook multiplication and we are not being carefull to reduce the limbs to 120 bits and considering overflows, so this product is being computed lazily. Those concerns will be covered later with the help of the borrow flags computed in the initial stage of the function.

After computing the whole expression, we need to apply the borrow to obtain the limbs in 120 bits. Here, we define the borrow value to $2^{246}$. Notice that $246 = 120 + 120 + 6$ which is the ammount of bits per limb in a product of two numbers of 64 limbs. This means that our implementation is limited to products of two numbers of at most 64 limbs, which is more than enough for real-world applications.

The last step, we need to check that the condition $t_0 * t_1 + t_4 - q \cdot c = 0$. In this case, we may have a situation in which the higher bits of a limb overlaps with the lower bits of the next limb. because of the subtractions. Therefore, we need to check that the lower 120 bits of a limb are zero and then carry the rest of the most significant bits to the next limb. This needs to be done starting from the least significant limb to the most significant one. To optimize this step, we can do the check by multiplying the limb by $2^{-120}$, and then we can constrain the result to be less than $2^{126}$ using a range proof. Notice that if there is a non-zero bit in the lower 120 bits, the multiplication with $2^{-120}$, this result will underflow and the value will wrap around. Hence the range check will not pass with significant probability (the probability that an underflow satisfies the range check is $2^{\text{Bits}(\mathbb{F})-126}$).

### Computation of the quotient and the borrow flags



### Addition

### Multiplication

#### Schoolbook multiplication

#### Karatsuba multiplication