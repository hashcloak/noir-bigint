// Copyright 2024 Zac Williamson

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// With changes from HashCloak

mod utils;
mod bignum_test;
mod fields;
mod mul;
mod test_params;

use dep::std;
use crate::utils::u60_representation::U60Repr;
use crate::utils::arrayX::ArrayX;
use crate::utils::split_bits;

/**
 * @brief BigNumParamsTrait defines a "field" with which to parametrise BigNum.
 * @description The "field" does not need to be prime, any value *should* work (TODO: test!)
**/
trait BigNumParamsTrait<N> {
    /**
     * @brief modulus: all BigNum operations are evaluated modulo this value
     **/
    fn modulus() -> [Field; N];

    /**
     * @brief double_modulus: used when performing negations and subtractions
     **/
    fn double_modulus() -> [Field; N];

    /**
     * @brief redc_param used for __barrett_reduction. See https://en.wikipedia.org/wiki/Barrett_reduction
     **/
    fn redc_param() -> [Field; N];

    /**
     * @brief k used for __barrett_reduction. Usually equals modulus_bits()
     *          but might be modulus_bits() + 1
     * TODO get more clarity about when the latter is needed
     **/
    fn k() -> u64;

    /**
     * @brief modulus_bits = log2(modulus) rounded up
     **/
    fn modulus_bits() -> u64;

    /**
     * @brief efficient multiplication of 2 N-length arrays. To use in constrained fn
     **/
    fn mult(a: [Field; N], b: [Field; N]) -> ArrayX<Field, N, 2>;
}

/**
 * @brief BNExpressionInput used to define inputs into `BigNum::evaluate_quadratic_expression`
 *        (evaluate_quadratic_expression is the basic building block for efficiently evaluating BigNum algebra)
**/
struct BNExpressionInput<N, Params> {
    value: BigNum<N, Params>,
    is_negative: bool,
}

impl<N, Params> BNExpressionInput<N, Params> {
    fn new(input: BigNum<N, Params>, _is_negative: bool) -> Self {
        BNExpressionInput { value: input, is_negative: _is_negative }
    }
}

struct BigNum<N,Params> {
    limbs: [Field; N],
}

impl<N, Params> BigNum<N, Params> {

    // ####################################################################################################################
    // ####################################################################################################################
    // ### C  O  N  S  T  R  U  C  T  O  R  S
    // ####################################################################################################################
    // ####################################################################################################################
    fn new() -> Self {
        BigNum { limbs: [0; N] }
    }

    fn one() -> Self {
        let mut result = BigNum::new();
        result.limbs[0] = 1;
        result
    }

    /**
     * @brief construct a BigNum instance out of an array of bytes in BIG ENDIAN format
     * @description: each 120-bit limb represents 15 bytes, we require that the size of the byte array
     *               is precisely large enough to cover Params::modulus_bits()
     * @param x: input byte array
     **/
    fn from_byte_be<NBytes>(x: [u8; NBytes]) -> Self where Params: BigNumParamsTrait<N> {
        let num_bits: u64 = NBytes * 8;
        let modulus_bits: u64 = Params::modulus_bits();
        assert(num_bits > modulus_bits);
        assert(num_bits - modulus_bits < 8);
        let mut result = BigNum::new();
        for i in 0..N {
            let mut limb: Field = 0;
            for j in 0..15 {
                limb *= 256;
                limb += x[i * 15 + j] as Field;
            }
            result.limbs[N - i - 1] = limb;
        }

        // max_bits_in_most_significant_byte should be known at comptime. if not...messy!
        let mut max_bits_in_most_significant_byte = num_bits - modulus_bits;
        if num_bits == modulus_bits {
            max_bits_in_most_significant_byte = 8;
        }
        let most_significant_byte: Field = x[N * 15 - 1] as Field;
        most_significant_byte.assert_max_bit_size(max_bits_in_most_significant_byte as u32);
        result
    }
    // ####################################################################################################################
    // ####################################################################################################################
    // ### U N C O N S T R A I N E D    F U N C T I O N S
    // ####################################################################################################################
    // ####################################################################################################################

    // N.B. not cryptographically secure! only use in tests
    unconstrained fn __derive_from_seed<SeedBytes>(seed: [u8; SeedBytes]) -> Self where Params: BigNumParamsTrait<N> {
        let mut rolling_seed = seed;
        let mut unreduced: Self = Self { limbs: [0; N] };

        let half_N: u64 = N / 2;
        for i in 0..(half_N) {
            let hash: [u8; 32] = std::hash::sha256(rolling_seed);
            let mut lo: Field = 0;
            let mut hi: Field = 0;
            for j in 0..15 {
                hi *= 256;
                lo *= 256;
                hi += hash[j] as Field;
                lo += hash[j + 15] as Field;
            }
            unreduced.limbs[2 * i] = hi;
            unreduced.limbs[2 * i + 1] = lo;
            rolling_seed[0] += 1;
        }
        if (half_N * 2 != N) {
            let hash: [u8; 32] = std::hash::sha256(rolling_seed);
            let mut hi: Field = 0;
            for j in 0..15 {
                hi *= 256;
                hi += hash[j] as Field;
            }
            unreduced.limbs[N - 1] = hi;
        }
        let to_reduce: ArrayX<Field, N, 2> = ArrayX { segments: [unreduced.limbs, [0; N]] };
        let (_, remainder) = BigNum::__barrett_reduction(to_reduce, Params::redc_param(), Params::k(), Params::modulus());
        BigNum { limbs: remainder }
    }

    unconstrained fn __validate_in_field_compute_borrow_flags(self: Self) -> [bool; N] where Params: BigNumParamsTrait<N> {
        let mut flags: [bool; N] = [false; N];
        let modulus: [Field; N] = Params::modulus();
        flags[0] = modulus[0].lt(self.limbs[0]);
        for i in 1..N - 1 {
            flags[i] = modulus[i].lt(self.limbs[i] + flags[i - 1] as Field);
        }
        flags
    }

    unconstrained fn __normalize_limbs<NumSegments>(x: ArrayX<Field, N, NumSegments>, range: u64) -> ArrayX<Field, N, NumSegments> {
        let mut normalized: ArrayX<Field, N, NumSegments> = ArrayX::new();
        let mut inp = x;
        for i in 0..(range - 1) {
            let (lo, hi) = split_bits::split_120_bits(inp.get(i));

            normalized.set(i, lo);
            inp.set(i + 1, inp.get(i + 1) + hi);
        }
        {
            let (lo, hi) = split_bits::split_120_bits(inp.get(range - 1));
            normalized.set(range - 1, lo);
            assert(hi == 0);
        }
        normalized
    }

    unconstrained fn __powmod(self: Self, exponent: Self) -> Self where Params: BigNumParamsTrait<N> {
        let x: U60Repr<N, 2> = U60Repr::from(exponent.limbs);

        let num_bits = Params::modulus_bits() + 1;

        let mut accumulator: Self = BigNum::one();

        for i in 0..num_bits {
            accumulator = accumulator.__mulmod(accumulator);
            if x.get_bit(num_bits - i - 1) {
                accumulator = accumulator.__mulmod(self);
            }
        }
        accumulator
    }

    unconstrained fn __invmod(self: Self) -> Self where Params: BigNumParamsTrait<N> {
        let modulus_u60: U60Repr<N, 2> = U60Repr::from(Params::modulus());
        let one_u60: U60Repr<N, 2> = U60Repr::from(BigNum::one().limbs);
        let exponent = modulus_u60.sub(one_u60.add(one_u60));
        self.__powmod(BigNum { limbs: U60Repr::into(exponent) })
    }

    unconstrained fn __divmod(self: Self, divisor: Self) -> Self where Params: BigNumParamsTrait<N> {
        let t0 = divisor.__invmod();
        self.__mulmod(t0)
    }

    unconstrained fn __barrett_reduction(
        x: ArrayX<Field, N, 2>,
        redc_param: [Field; N],
        k: u64,
        modulus: [Field; N]
    ) -> ([Field; N], [Field; N]) {
        let mut mulout: ArrayX<Field, N, 3>  = ArrayX { segments: [[0; N]; 3] };
        for i in 0..(N + N) {
            for j in 0..N {
                mulout.add_assign(i + j, x.get(i) * redc_param[j]);
            }
        }
        mulout = BigNum::__normalize_limbs(mulout, 3 * N - 2);
        let mulout_u60: U60Repr<N, 6> = U60Repr::new(mulout);
        let mut quotient_u60 = mulout_u60.shr((k + k));

        // N.B. we assume that the shifted quotient cannot exceed 2 times original bit size.
        //      (partial_quotient should be just slightly larger than the modulus, we could probably represent with a size N+1 array)
        let partial_quotient: ArrayX<Field, N, 2> = quotient_u60.into_arrayX();

        // quotient_mul_modulus can never exceed input value `x` so can fit into size-2 array
        let mut quotient_mul_modulus: ArrayX<Field, N, 2>  = ArrayX { segments: [[0; N]; 2] };
        let mut quotient_mul_modulus_normalized: ArrayX<Field, N, 2>  = ArrayX { segments: [[0; N]; 2] };
        for j in 0..N {
            for i in 0..(N + N - j) {
                quotient_mul_modulus.add_assign(i + j, partial_quotient.get(i) * modulus[j]);
            }
        }

        for i in 0..(N + N - 1) {
            let (lo, hi) = split_bits::split_120_bits(quotient_mul_modulus.get(i));
            quotient_mul_modulus_normalized.set(i, lo);
            // TODO: what is faster, leaving this if statement in or out?
            // (array is size-1 too large so we can tolerate adding 0 into max element)
            //if (i + 1 < N + N - 1) {
            quotient_mul_modulus.add_assign(i + 1, hi);
            //}
        }
        let quotient_mul_modulus_u60: U60Repr<N, 4> = U60Repr::new(quotient_mul_modulus_normalized);

        let x_u60 : U60Repr<N, 4> = U60Repr::new(x);

        let mut remainder_u60 = x_u60 - quotient_mul_modulus_u60;

        let modulus_u60: U60Repr<N, 4> = U60Repr::from(modulus);
        if (remainder_u60.gte(modulus_u60)) {
            remainder_u60 = remainder_u60 - modulus_u60;
            quotient_u60.increment();
        }

        (U60Repr::into(quotient_u60), U60Repr::into(remainder_u60))
    }

    unconstrained fn __mulmod_with_quotient(self, rhs: Self) -> (Self, Self) where Params: BigNumParamsTrait<N> {
        let mut mul: ArrayX<Field, N, 2> = ArrayX::new();
        for i in 0..N {
            for j in 0..N {
                mul.add_assign(i + j, self.limbs[i] * rhs.limbs[j]);
            }
        }
        let (q, r) = BigNum::__barrett_reduction(
            BigNum::__normalize_limbs(mul, N + N - 1),
            Params::redc_param(),
            Params::k(),
            Params::modulus()
        );

        (Self { limbs: q }, Self { limbs: r })
    }

    unconstrained fn __mulmod(self, rhs: Self) -> Self where Params: BigNumParamsTrait<N> {
        let (_, b) = self.__mulmod_with_quotient(rhs);
        b
    }

    unconstrained fn __addmod(self, rhs: Self) -> Self where Params: BigNumParamsTrait<N> {
        let x_u60 : U60Repr<N, 2> = U60Repr::from(self.limbs);
        let y_u60 : U60Repr<N, 2> = U60Repr::from(rhs.limbs);

        let mut z_u60 = x_u60 + y_u60;

        let modulus_u60 : U60Repr<N,2> = U60Repr::from(Params::modulus());
        if z_u60.gte(modulus_u60) {
            z_u60 = z_u60 - modulus_u60;
        }
        Self { limbs: U60Repr::into(z_u60) }
    }

    /**
     * @brief given an input `x`, compute `2p - x` (unconstrained)
     *
     * @description we subtract the input from double the modulus, because all constrained BigNum operations
     *              only guarantee that the output is in the range [0, ceil(log2(p))].
     *              I.E. the input may be larger than the modulus `p`.
     *              In order to ensure this operation does not underflow, we compute `2p - x` instead of `p - x`.
     *              N.B. constrained BigNum operations do not fully constrain outputs to be in the range [0, p-1]
     *              because such a check is expensive and usually unneccesary.
     */
    unconstrained fn __negate(self) -> Self where Params: BigNumParamsTrait<N> {
        let f: [Field; N] = self.limbs;
        let x_u60 : U60Repr<N, 2> = U60Repr::from(f);
        let modulus_u60 : U60Repr<N, 2> = U60Repr::from(Params::double_modulus());
        Self { limbs: U60Repr::into(modulus_u60 - x_u60) }
    }

    /**
     * @brief given inputs `x, y` compute 2p + x - y (unconstrained)
     * @description see `__negate` for why we use 2p instead of p
     **/
    unconstrained fn __submod(self, rhs: Self) -> Self where Params: BigNumParamsTrait<N> {
        self.__addmod(rhs.__negate())
    }

    /**
     * @brief Computes the result of a linear combination of BNExpressionInput values (unconstrained)
     * @description This method computes separate totals for positive/negative BNExpressionInput values.
     *              This is so that we can later evaluate which BigNum limbs will underflow when combining positive/negative sums
     **/
    unconstrained fn __add_linear_expression<M>(x: [BNExpressionInput<N, Params>; M]) -> ([Field; N], [Field; N]) where Params: BigNumParamsTrait<N> {
        // TODO, validate we do not overflow N2 when multiplying and N when adding
        let mut lhs_sum_p: [Field; N] = [0; N];
        let mut lhs_sum_n: [Field; N] = [0; N];
        let modulus2: [Field;N] = Params::double_modulus();
        for i in 0..M {
            if (x[i].is_negative) {
                for j in 0..N {
                    lhs_sum_p[j] = lhs_sum_p[j] + modulus2[j];
                    lhs_sum_n[j] = lhs_sum_n[j] + x[i].value.limbs[j];
                }
            } else {
                for j in 0..N {
                    lhs_sum_p[j] = lhs_sum_p[j] + x[i].value.limbs[j];
                }
            }
        }
        // problem if we normalize when used in computing quotient
        (lhs_sum_p, lhs_sum_n)
        //   let result_p: ArrayX<Field, N, 1> = BigNum::__normalize_limbs(ArrayX::from_array(lhs_sum_p), N);
        //  let result_n: ArrayX<Field, N, 1> = BigNum::__normalize_limbs(ArrayX::from_array(lhs_sum_n), N);
        //  (result_p.segments[0], result_n.segments[0])
    }

    /**
     * @brief Given a degree-2 BigNum expression that is equal to 0 mod p, compute the quotient and borrow flags 
     * @description The expression is of the form:
     *
     * \sum_{i=0}^{NUM_PRODUCTS - 1} ((\sum_{j=0}^{LHS_N-1}lhs[i][j]) * (\sum_{j=0}^{RHS_N-1}rhs[i][j])) + \sum_{i=0}^{ADD_N - 1}linear_terms[i] = quotient * modulus
     *
     * The intent is to capture an arbitrary degree-2 expression within the limitations of Noir (no efficient dynamically-sized vectors)
     *
     * When performing BigNum arithmetic, we want to represent desired BigNum operations in a way that minimizes the number of modular reductions that are required.
     * This can be achieved by minimizing the number of degree-2 relations required.
     *
     * The borrow flags describe whether individual Field limbs will underflow when evaluating the above relation.
     * For example, when computing the product a * b - q * p = 0, it is possible that:
     *      1. a[0]*b[0] - p[0]*q[0] = -2^{120}
     *      2. a[0]*b[1] + a[1]*b[0] - p[0]*q[1] - p[1]*q[0] = 1
     * In the above example, the value represented by these two limbs is zero despite each limb being nonzero.
     * In this case, to correctly constrain the result, we must add (at least) 2^{120} from the first limb and subtract 1 from the second.
     *
     * @param lhs_terms a 2D array of BNExpressionInput
     * @param rhs_terms a 2D array of BNExpressionInput
     * @param linear_terms a 2D array of BNExpressionInput
     **/
    unconstrained fn __compute_quadratic_expression_quotient<LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_terms: [[BNExpressionInput<N, Params>; LHS_N]; NUM_PRODUCTS],
        rhs_terms: [[BNExpressionInput<N, Params>; RHS_N]; NUM_PRODUCTS],
        linear_terms: [BNExpressionInput<N, Params>; ADD_N]
    ) -> (Self, ArrayX<Field, N, 2>) where Params: BigNumParamsTrait<N> {
        // TODO, validate we do not overflow N2 when multiplying and N when adding
        let mut lhs_p: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut lhs_n: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut rhs_p: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut rhs_n: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut add_p: [Field; N] = [0; N];
        let mut add_n: [Field; N] = [0; N];

        for i in 0..NUM_PRODUCTS {
            let (l_p, l_n): ([Field; N], [Field; N]) = BigNum::__add_linear_expression(lhs_terms[i]);
            let (r_p, r_n): ([Field; N], [Field; N]) = BigNum::__add_linear_expression(rhs_terms[i]);
            lhs_p[i] = l_p;
            lhs_n[i] = l_n;
            rhs_p[i] = r_p;
            rhs_n[i] = r_n;
        }

        let (add_p, add_n): ([Field; N], [Field; N]) = BigNum::__add_linear_expression(linear_terms);

        // Multiplication of two N-limb numbers gives us a (2N - 1) limb number.
        // Hence we use ArrayX.
        let mut mulout_p: ArrayX<Field, N,2> = ArrayX::new();
        let mut mulout_n: ArrayX<Field, N,2> = ArrayX::new();

        for i in 0..N {
            for j in 0..N {
                for k in 0..NUM_PRODUCTS {
                    assert(lhs_n[k][i] == 0);
                    assert(rhs_n[k][i] == 0);
                    mulout_p.add_assign(i + j, lhs_p[k][i] * rhs_p[k][j]);
                    mulout_n.add_assign(i + j, lhs_n[k][i] * rhs_n[k][j]);
                }
            }
            mulout_p.add_assign(i, add_p[i]);
            mulout_n.add_assign(i, add_n[i]);
        }

        // Normalizes each limb to be in 120-bits.
        let T0: ArrayX<Field, N, 2> = BigNum::__normalize_limbs(mulout_p, N + N - 1);
        let T1: ArrayX<Field, N, 2> = BigNum::__normalize_limbs(mulout_n, N + N - 1);

        // Takes each multiplication output with (2N - 1) limbs with 120-bit numbers
        // and converts it into limbs of 60 bits. Therefore, we obtain 4N - 2 limbs
        // that can be stored in 4N limbs.
        let mulout_pu60: U60Repr<N, 4> = U60Repr::new(T0);
        let mulout_nu60: U60Repr<N, 4> = U60Repr::new(T1);

        // into_array() converts the 60-bit limbs into 120-bit limbs. So, we are subtracting
        // and converting the result again into a 120-bit limb format with normalization.
        // Again, we obtain 2N - 1 limbs.
        let relation_result: ArrayX<Field, N, 2> = BigNum::__normalize_limbs((mulout_pu60 - mulout_nu60).into_arrayX(), N + N - 1);

        let modulus: [Field; N] = Params::modulus();
        let (quotient, remainder) = BigNum::__barrett_reduction(relation_result, Params::redc_param(), Params::k(), modulus);
        assert(remainder == [0; N]);

        for i in 0..N {
            for j in 0..N {
                mulout_n.add_assign(i + j, quotient[i] * modulus[j]);
            }
        }

        // compute borrow flags from mulout_p and mulout_n
        let mut borrow_flags: ArrayX<Field, N, 2> = ArrayX::new();
        let borrow_shift: Field = 0x40000000000000000000000000000000000000000000000000000000000000; // 2^{246}
        let borrow_carry: Field = 0x40000000000000000000000000000000; // 2^{246 - 120} = 2^{126}
        let two_pow_120: Field = 0x1000000000000000000000000000000;
        let downshift: Field = 1 / two_pow_120;

        // determine whether we need to borrow from more significant limbs.
        // initial limb is "simple" comparison operation
        // TODO: check how expensive `lt` operator is w.r.t. witness generation
        borrow_flags.set(0, mulout_p.get(0).lt(mulout_n.get(0)) as Field);
        // we have 2N - 2 borrow flags. The number of limbs from our product computation is 2N - 1
        // and there is nothing to borrow against for the final limb.
        let mut hi_bits = (mulout_p.get(0) - mulout_n.get(0) + (borrow_flags.get(0) * borrow_shift)) * downshift;
        for i in 1..(N + N - 2) {
            // compute the contribution from limb `i-1` that gets added into limb `i`, and add into limb `i`
            // let hi_bits = (mulout_p.get(i - 1) - mulout_n.get(i - 1) + (borrow_flags.get(i - 1) * borrow_shift))
            //     * downshift;
            mulout_p.add_assign(i, hi_bits);

            // determine whether negative limb values are greater than positive limb values
            let underflow: Field = mulout_p.get(i).lt(mulout_n.get(i) + (borrow_flags.get(i - 1) * borrow_carry)) as Field;
            borrow_flags.set(i, underflow);

            hi_bits = (mulout_p.get(i) - mulout_n.get(i) + (borrow_flags.get(i) * borrow_shift)
                - (borrow_flags.get(i - 1) * borrow_carry)) * downshift;
        }

        (Self { limbs: quotient }, borrow_flags)
    }

    // ####################################################################################################################
    // ####################################################################################################################
    // ### C O N S T R A I N E D    F U N C T I O N S
    // ####################################################################################################################
    // ####################################################################################################################
    fn validate_in_range(self) where Params: BigNumParamsTrait<N> {
        for i in 0..(N - 1) {
            self.limbs[i].assert_max_bit_size(120);
        }
        let final_limb_bits = Params::modulus_bits() - ((N - 1) * 120);
        self.limbs[N - 1].assert_max_bit_size(final_limb_bits as u32);
    }

    /**
     * @brief Validate self != other
     * @details If A == B, then A == B mod N.
     *          We can efficiently evaluate A == B mod N where N = circuit modulus
     *          This method is *sound*, but not *complete* (i.e. A != B but A == B mod N)
     *          However the probability of an honest Prover being unable to satisfy this check is tiny!
     *          (todo: compute how tiny)
     **/
    fn assert_is_not_equal(self, other: Self) where Params: BigNumParamsTrait<N> {
        let mut lhs: Field = 0;
        let mut rhs: Field = 0;
        let mut modulus_mod_n: Field = 0;
        let mut two_pow_120: Field = 0x1000000000000000000000000000000;
        let modulus = Params::modulus();
        for i in 0..N {
            lhs *= two_pow_120;
            rhs *= two_pow_120;
            modulus_mod_n *= two_pow_120;
            lhs += self.limbs[N - i - 1];
            rhs += other.limbs[N - i - 1] ;
            modulus_mod_n += modulus[N - i - 1];
        }

        // lhs can be either X mod N or P + X mod N
        // rhs can be either Y mod N or P + Y mod N
        // If lhs - rhs = 0 mod P then lhs - rhs = 0, P or -P mod N
        let mut diff = lhs - rhs;
        let mut target = diff * (diff + modulus_mod_n) * (diff - modulus_mod_n);
        assert(target != 0, "asssert_is_not_equal fail");
    }

    /**
     * @brief validate quotient produced from `evaluate_quadratic_expression` is well-formed
     * @description because the inputs into evaluate_quadratic_expression may cause the quotient to extend beyond `Params::modulus_bits`.
     *              We allow the quotient to extend 6 bits beyond Params::modulus_bits()
     *              Why is this?
     *              several factors:    1. quotient * modulus , limbs cannot overflow field boundary (254 bits)
     *                                  2. in `evaluate_quadratic_expression`, we require that for `expression - quotient * modulus`,
     *                                     limbs cannot exceed 246 bits (246 magic number due to a higher number adding extra range check gates)
     *              because of factor 2 and the fact that modulus limbs are 120 bits, quotient limbs cannot be >126 bits
     *
     *              Note: doesn't this mean that final_limb_bits should be constrained to be 126 bits, not modulus_bits() - ((N - 1) * 120) + 6?
     *              TODO: think about this more! we want the range constraint we apply to be as small as allowable as this is more efficient
     **/
    fn validate_quotient_in_range(self) where Params: BigNumParamsTrait<N> {
        for i in 0..(N) {
            self.limbs[i].assert_max_bit_size(120);
        }
        // Note: replace magic number 6 with definition
        let final_limb_bits = Params::modulus_bits() - ((N - 1) * 120) + 6;
        self.limbs[N - 1].assert_max_bit_size(final_limb_bits as u32);
    }

    fn validate_in_field(self: Self) where Params: BigNumParamsTrait<N> {
        // N.B. need to combine with validate_in_range if `self` limbs have not been range constrained
        let mut p_minus_self: [Field; N] = [0; N];
        let modulus: [Field; N] = Params::modulus();
        for i in 0..N {
            p_minus_self[i] = modulus[i] - self.limbs[i];
        }
        let borrow_flags = self.__validate_in_field_compute_borrow_flags();
        let two_pow_120: Field = 0x1000000000000000000000000000000;
        p_minus_self[0] += borrow_flags[0] as Field * two_pow_120;
        for i in 1..N - 1 {
            p_minus_self[i] += (borrow_flags[i] as Field * two_pow_120 - borrow_flags[i-1] as Field);
        }
        p_minus_self[N - 1] -= borrow_flags[N - 2] as Field;
        (Self { limbs: p_minus_self }).validate_in_range();
    }

    /**
     * @brief conditional_select given the value of `predicate` return either `self` (if 0) or `other` (if 1)
     * @description should be cheaper than using an IF statement (TODO: check!)
     **/
    fn conditional_select(self: Self, other: Self, predicate: bool) -> Self where Params: BigNumParamsTrait<N> {
        let mut result: Self = Self { limbs: [0; N] };

        for i in 0..N {
            result.limbs[i] = (predicate as Field) * (other.limbs[i] - self.limbs[i]) + self.limbs[i];
        }
        result
    }

    /**
     * @brief Constrain a degree-2 BigNum expression to be equal to 0 modulo Params::modulus()
     * @description The expression is of the form (when evaluated as an integer relation):
     *
     * \sum_{i=0}^{NUM_PRODUCTS - 1} ((\sum_{j=0}^{LHS_N-1}lhs[i][j]) * (\sum_{j=0}^{RHS_N-1}rhs[i][j])) + \sum_{i=0}^{ADD_N - 1}linear_terms[i] - quotient * modulus = 0
     *
     * The intent is to capture an arbitrary degree-2 expression within the limitations of Noir (no efficient dynamically-sized vectors)
     *
     * When performing BigNum arithmetic, we want to represent desired BigNum operations in a way that minimizes the number of modular reductions that are required.
     * This can be achieved by minimizing the number of degree-2 relations required.
     *
     * The expensive parts of this algorithm are the following:
     *      1. evaluating the limb products required to compute `lhs * rhs`
     *      2. applying range constraints to validate the result is 0
     *
     * Range constraints are needed for the following reason:
     * When evaluating the above expression over N-limb BigNum objects, the result will consist of 2N - 1 limbs.
     * Each limb will be in the range [0, ..., 2^{240 + twiddle_factor} - 1] (twiddle_factor needs to be less than 6).
     * Because of the subtractions, the limbs may underflow and represent NEGATIVE values.
     * To account for this, we allow the Prover to borrow values from more significant limbs and add them into less significant limbs
     * (explicitly, we can borrow 2^{126} from limb `i + 1` to add `2^{246}` into `i`).
     * To ensure this has been done correctly, we validate that the borrow-adjusted limbs are all-zero for the first 120 bits.
     * We do *this* by multiplying the borrow-adjusted limbs by 1 / 2^{120} modulo CircutModulus, and we validate the result is in the range [0, ..., 2^{126} - 1].
     * TODO: explain why this check works. It's statistically sound but not perfectly sound. Chance of the check failing is ~1 in 2^{120}
     * I believe this is the most efficient way of performing the zero-check for this relation as it only requires `2N - 2` 126-bit range checks.
     * TODO: explain why we apply a 126-bit range check, this feels like a magic number
     * (it is. we could go higher, up to the number of bits in the CircuitModulus - 121, but 126 *should be* sufficient and is much cheaper)
     * TODO: apply checks in this method to validate twiddle_factor does not exceed 6
     * 
     * @param lhs_terms a 2D array of BNExpressionInput
     * @param rhs_terms a 2D array of BNExpressionInput
     * @param linear_terms a 2D array of BNExpressionInput
     **/
    fn evaluate_quadratic_expression<LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_products: [[BNExpressionInput<N, Params>; LHS_N]; NUM_PRODUCTS],
        rhs_products: [[BNExpressionInput<N, Params>; RHS_N]; NUM_PRODUCTS],
        linear_terms: [BNExpressionInput<N, Params>; ADD_N]
    ) where Params: BigNumParamsTrait<N> {
        // use an unconstrained function to compute the value of the quotient
        let (quotient, borrow_flags): (Self, ArrayX<Field, N, 2>) = BigNum::__compute_quadratic_expression_quotient(lhs_products, rhs_products, linear_terms);
        // constrain the quotient to be in the range [0, ..., 2^{m} - 1], where `m` is log2(modulus) rounded up.
        // Additionally, validate quotient limbs are also in the range [0, ..., 2^{120} - 1]
        quotient.validate_quotient_in_range();
        // TODO, validate we do not overflow N2 when multiplying and N when adding
        // (should be a compile-time check...unconstrained function?)

        // Compute the linear sums that represent lhs_1, rhs_1, lhs_2, rhs_2, add
        let mut t0: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut t1: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
        let mut t4: [Field; N] = [0; N];
        let double_modulus: [Field; N] = Params::double_modulus();
        for k in 0..NUM_PRODUCTS {
            for i in 0..N {
                for j in 0..LHS_N {
                    // note: if is_negative is not known at comptime this is very expensive
                    let is_negative: bool = lhs_products[k][j].is_negative;
                    if (is_negative) {
                        t0[k][i] -= lhs_products[k][j].value.limbs[i];
                        t0[k][i] += double_modulus[i];
                    } else {
                        t0[k][i] += lhs_products[k][j].value.limbs[i];
                    }
                }
                for j in 0..RHS_N {
                    let is_negative: bool = rhs_products[k][j].is_negative;
                    if (is_negative) {
                        t1[k][i] -= rhs_products[k][j].value.limbs[i];
                        t1[k][i] += double_modulus[i];
                    } else {
                        t1[k][i] += rhs_products[k][j].value.limbs[i];
                    }
                }
            }
        }
        for i in 0..N {
            for j in 0..ADD_N {
                let is_negative: bool = linear_terms[j].is_negative;
                if (is_negative) {
                    t4[i] -= linear_terms[j].value.limbs[i];
                    t4[i] += double_modulus[i];
                } else {
                    t4[i] += linear_terms[j].value.limbs[i];
                }
            }
        }

        // TODO: Fix this comment given that t3 does not exist.
        // We want to evaluate that t0 * t1 + t2 * t3 + t4 - Quotient * Modulus = 0, evaluated over the integers
        // For this we need to be able to borrow values from more-significant limbs into less-significant limbs,
        // so that we can ensure that no limbs will underflow for an honest Prover
        let mut product_limbs: ArrayX<Field, N,2> = ArrayX::new();
        //       let fff: [Field; N] = quotient.limbs;
        //      let mut borrow_flags: ArrayX<Field, N,2> = BigNum::get_borrow_flags3(t0, t1, t2, t3, t4, fff, Params::modulus());

        // Compute the product t0 * t1 + t2 * t3 + t4 - Quotient * Modulus
        let modulus: [Field; N] = Params::modulus();

        // Products
        for k in 0..NUM_PRODUCTS {
          // This does the most efficient multiplication based on array length N
          let mult_res = Params::mult(t0[k], t1[k]);
          for i in 0..N+N-1 {
            product_limbs.add_assign(i, mult_res.get(i));
          }
        }

        let product_q_p = Params::mult(quotient.limbs, modulus);
        for i in 0..N+N-1 {
            product_limbs.sub_assign(i, product_q_p.get(i));
        }

        for i in 0..N {
            product_limbs.add_assign(i, t4[i]);
        }

        // each limb product represents the sum of 120-bit products.
        // by setting the borrow value to 2^246 we are restricting this method's completeness to expressions
        // where no more than 64 limb products are summed together.
        // TODO: check in unconstrained function that this condition is satisfied
        // TODO: define trade-offs regarding the value of borrow_shift
        // (the larger the value, the greater the range check that is required on product_limbs)
        // (126-bit range check is a sweet spot for the barretenberg backend as it decomposes into 9 14-bit range checks)
        // (the barretenberg backend can evaluate these in 5.25 gates. 127 bits costs 6.5 gates)
        let borrow_shift: Field = 0x40000000000000000000000000000000000000000000000000000000000000; // 2^{246}
        let borrow_carry: Field = 0x40000000000000000000000000000000; // 2^{246 - 120} = 2^{126}

        // N.B. borrow_flags is `Field` type because making it `bool` would apply boolean constraints to all `N2` array entries.
        //      We only use `N2 - 2` borrow flags so applying 1-bit range checks on the array elements we use is more efficient.
        // TODO: Once it is possible to perform arithmetic on generics we can use `borrow_flags: [bool;N+N-2]` to avoid this issue
        borrow_flags.get(0).assert_max_bit_size(1);
        product_limbs.add_assign(0, borrow_flags.get(0) * borrow_shift);
        for i in 1..(N + N - 2) {
            borrow_flags.get(i).assert_max_bit_size(1);
            product_limbs.add_assign(
                i,
                (borrow_flags.get(i) * borrow_shift - borrow_flags.get(i - 1) * borrow_carry)
            );
        }
        product_limbs.sub_assign(N + N - 2, borrow_flags.get(N + N - 3) * borrow_carry);

        // Final step: Validate `product_limbs` represents the integer value `0`
        // Each element `i` in `product_limbs` overlaps in bitrange with element `i+1`, EXCEPT for the low 120 bits
        // i.e. we need to do the following for each limb `i`:
        //      1. validate the limb's low-120 bits equals zero
        //      2. compute the limb "carry" by right-shifting by 2^{120}
        //      3. add the carry into limb `i+1`
        // We can efficiently do all of the above by multiplying the limb by 2^{-120} and constraining the result to be <2^{126}
        // (if the low 120 bits are nonzero the result will underflow and product a large value that cannot be range constrained)
        // (the probability of an underflow value satisfying a 126-bit range constraint is approx. 2^{k - 126},
        //  where k is the number of bits in the prime field)
        // We then add the result into the next limb and repeat.
        let hi_shift: Field = 0x1000000000000000000000000000000;
        let hi_downshift: Field = 1 / hi_shift;
        for i in 0..N + N - 2 {
            product_limbs.mul_assign(i, hi_downshift);
            // std::as_witness(product_limbs.get(i));
            product_limbs.get(i).assert_max_bit_size(126); // N.B. is this sufficient? going beyond 126 costs us 1 gate per limb
            product_limbs.add_assign(i + 1, product_limbs.get(i));
        }
        // the most significant limb has no limb to "carry" values into - the entire limb must equal zero
        assert(product_limbs.get(N + N - 2) == 0);
    }
}

impl<N, Params> std::ops::Add for BigNum<N, Params> where Params: BigNumParamsTrait<N> {
    // Note: this method is expensive! Try to craft quadratic relations and directly evaluate them
    //       via evaluate_quadratic_expression
    fn add(self, other: Self) -> Self {
        let result = self.__addmod(other);
        // N.B. using `[]` as a parameter input does not produce a 2D array of size 0 (it's a 2D array of size-1 where the inner array is empty)
        let empty_expression: [[BNExpressionInput<N, Params>; 0]; 0] = [];
        BigNum::evaluate_quadratic_expression(
            empty_expression,
            empty_expression,
            [BNExpressionInput::new(self, false), BNExpressionInput::new(other, false), BNExpressionInput::new(result, true)]
        );
        result
    }
}

impl<N, Params> std::ops::Sub for BigNum<N, Params> where Params: BigNumParamsTrait<N> {
    // Note: this method is expensive! Try to craft quadratic relations and directly evaluate them
    //       via evaluate_quadratic_expression
    fn sub(self, other: Self) -> Self {
        let result = self.__submod(other);
        // N.B. using `[]` as a parameter input does not produce a 2D array of size 0 (it's a 2D array of size-1 where the inner array is empty)
        let empty_expression: [[BNExpressionInput<N, Params>; 0]; 0] = [];
        BigNum::evaluate_quadratic_expression(
            empty_expression,
            empty_expression,
            [BNExpressionInput::new(self, true), BNExpressionInput::new(other, false), BNExpressionInput::new(result, false)]
        );
        result
    }
}

impl<N, Params> std::ops::Mul for BigNum<N, Params> where Params: BigNumParamsTrait<N> {
    // Note: this method is expensive! Try to craft quadratic relations and directly evaluate them
    //       via evaluate_quadratic_expression
    // e.g. performing a sum of multiple multiplications and additions via `evaluate_quadratic_expression`
    //      will create much fewer constraints than calling `mul` and `add` directly
    fn mul(self, other: Self) -> Self {
    let result = self.__mulmod(other);
        BigNum::evaluate_quadratic_expression(
            [[BNExpressionInput::new(self, false)]],
            [[BNExpressionInput::new(other, false)]],
            [BNExpressionInput::new(result, true)]
        );
        result
    }
}

impl<N, Params> std::ops::Div for BigNum<N, Params> where Params: BigNumParamsTrait<N> {
    // Note: this method is expensive! Witness computation is extremely expensive as it requires modular exponentiation
    fn div(self, other: Self) -> Self {
        let result = self.__divmod(other);
        BigNum::evaluate_quadratic_expression(
            [[BNExpressionInput::new(result, false)]],
            [[BNExpressionInput::new(other, false)]],
            [BNExpressionInput::new(self, true)]
        );
        result
    }
}

impl<N, Params> std::cmp::Eq for BigNum<N, Params> where Params: BigNumParamsTrait<N> {
    // Note: this method is expensive! Witness computation is extremely expensive as it requires modular exponentiation
    fn eq(self, other: Self) -> bool {
        self.limbs == other.limbs
    }
}
