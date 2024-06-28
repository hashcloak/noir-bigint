use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::bignum_test::{test_mul, test_add, test_div, test_invmod, assert_is_not_equal, assert_is_not_equal_fail, assert_is_not_equal_overloaded_lhs_fail, assert_is_not_equal_overloaded_rhs_fail, assert_is_not_equal_overloaded_fail};
use crate::mul::schoolbook_mult;

struct Test250NonPrimeParams {} 

impl BigNumParamsTrait<3> for Test250NonPrimeParams {
  // p = 1361178060504921827139522133321204869010984103087287764085951217604594813629
  fn modulus() -> [Field; 3] {
    [70845458779269151261553545303607997, 531000421149798835905479273028140712, 770]
  }

  fn double_modulus() -> [Field; 3] {
    [141690917558538302523107090607215994, 1062000842299597671810958546056281424, 1540]
  }

  // TODO which value should this have?
  // multiplication passes with both options
  fn redc_param() -> [Field; 3] {
    // floor(2^(2*250) / p)
    // 2404821751741939535213183860107145128251202395965182430330687029137119422122
    [933417134751064651162346767373084330, 107503437342275879432022793042152706, 1361]

    // floor(2^(2*251) / p)
    // 9619287006967758140852735440428580513004809583860729721322748116548477688491
    // [1075212547434426858841772948931648171, 430013749369103517728091172168610826, 5444]
  }

  fn modulus_bits() -> u64 {
    250
  }

  fn mult(a: [Field; 3], b: [Field; 3]) -> ArrayX<Field, 3, 2> {
    schoolbook_mult(a,b)
  }
}


#[test]
fn test_mul_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    test_mul(stub);
}

#[test]
fn test_add_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    test_add(stub);
}

// Fails because div uses the inverse, which is a method that assumes modulus is prime
#[test]
fn test_div_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    test_div(stub);
}

// also fails, for same reason as above
#[test]
fn test_invmod_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    test_invmod(stub);
}

#[test]
fn test_assert_is_not_equal_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    assert_is_not_equal(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_fail_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    assert_is_not_equal_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_lhs_fail_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_lhs_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_rhs_fail_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_rhs_fail(stub);
}

#[test(should_fail_with = "asssert_is_not_equal fail")]
fn test_assert_is_not_equal_overloaded_fail_250_nonprime() {
    let stub: BigNum<3, Test250NonPrimeParams> = BigNum::new();
    assert_is_not_equal_overloaded_fail(stub);
}
