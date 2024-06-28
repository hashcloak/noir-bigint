use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::bignum_test::{test_mul, test_add, test_div, test_invmod, assert_is_not_equal, assert_is_not_equal_fail, assert_is_not_equal_overloaded_lhs_fail, assert_is_not_equal_overloaded_rhs_fail, assert_is_not_equal_overloaded_fail};
use crate::mul::schoolbook_mult;

struct Test256PrimeParams {} 

impl BigNumParamsTrait<3> for Test256PrimeParams {
  // p = 60366135963840513237386038157515114888970572001086812435081366530276734345813
  fn modulus() -> [Field; 3] {
    [1046428477924633644898525967721505365, 29452149938442564262965797568607232, 34166]
  }

  fn double_modulus() -> [Field; 3] {
    [763628960064351416893244875162666154, 58904299876885128525931595137214465, 68332]
  }

  fn redc_param() -> [Field; 3] {
    // floor(2^(2*256) / p)
    // 222108102761023367492505251696509629421921914495786610938039468689099900314202
    [1029374792312756241085125999351554650, 971949030811144649531952005452139969, 125708]
  }

  fn modulus_bits() -> u64 {
    256
  }

  fn mult(a: [Field; 3], b: [Field; 3]) -> ArrayX<Field, 3, 2> {
    schoolbook_mult(a,b)
  }
}



#[test]
fn test_mul_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    test_mul(stub);
}

#[test]
fn test_add_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    test_add(stub);
}

#[test]
fn test_div_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    test_div(stub);
}

#[test]
fn test_invmod_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    test_invmod(stub);
}

#[test]
fn test_assert_is_not_equal_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    assert_is_not_equal(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_fail_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    assert_is_not_equal_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_lhs_fail_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_lhs_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_rhs_fail_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_rhs_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_fail_256_prime() {
    let stub: BigNum<3, Test256PrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_fail(stub);
}
