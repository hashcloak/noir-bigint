# Noir BigInt documentation

`noir-bigint` is a library that implements big-integers in Noir as a utility to develop other cryptographic primitives and tools for the Noir ecosystem. In this document, you will find all the documentation related with the implementation of the mentioned library from both theoretical and practical perspective.

## The goal

The goal is to implement a library that evaluates operations modulo an integer $p$ so that both the operands and the modulus can have arbitrary bit lengths. We will represent the operands and the modulus as $l$-bit big-integers. Each number will be defined as an array of $d$-bit *limbs*. Therefore, each value will need $N = \lceil\frac{l}{d}\rceil$ limbs for its representation.

Once the representation is defined, we want to expose an API that allows developers to write modular arithmetic zero-knowledge proofs using this big-integer modulus representation. Concretely, given $c \in \mathbb{Z}_p$, a prover wants to prove that he knows $a, b \in \mathbb{Z}_p$, such that $c$ is the sum or the product of $a$ and $b$ modulo $p$. This modular arithmetic is relevant in other cryptographic constructions like RSA signature schemes.

In the context of ZK-proofs, choosing $d$ is an important task, given that it will affect the efficiency of the proof generation. The algorithms considered in the library require approximately $O(N^{1.5})$ multiplications and additions and $O(l)$ range checks. As we mentioned before, $d$ is inversely proportional to $N$. Hence, a large $d$ would be a good choice for a large modulus. However, if the modulus is small, it is best to choose a small $d$ to reduce the complexity of the algorithms.

In the rest of the document and the implementation, we will consider $d = 120$ as a reasonable choice of parameters. Also, in the implementation, we consider $N$ to be fixed because of the technical limitations of Noir, as the library does not support an efficient mechanism to store the limbs dynamically like vectors. Hence, we are limited to using fixed-length arrays to represent the collection of limbs for a number. To give more freedom during circuit development, the API is designed so that the programmer can set the value of $N$ at compile time.

## BigInt primer



## Addition

## Multiplication

### Schoolbook multiplication

### Karatsuba multiplication