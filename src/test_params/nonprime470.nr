use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::bignum_test::{
    test_mul, test_add, test_div, test_invmod, assert_is_not_equal, assert_is_not_equal_fail,
    assert_is_not_equal_overloaded_lhs_fail, assert_is_not_equal_overloaded_rhs_fail,
    assert_is_not_equal_overloaded_fail
};
use crate::mul::{schoolbook_mult, karatsuba_mult_4};

struct Test470NonPrimeParams {}

impl BigNumParamsTrait<4> for Test470NonPrimeParams {
  fn modulus() -> [Field; 4] {
    [1168279869308004741471899385850824248, 717609637354522971790516049017740648, 119224995026414384427301864045239302, 1265534252738442765904613958755742]
  }

  fn double_modulus() -> [Field; 4] {
    [1007331742831093610039991711421303920, 105991278924130070677225037755136721, 238449990052828768854603728090478605, 2531068505476885531809227917511484]
  }

  fn redc_param() -> [Field; 4] {
    // floor(2^(2*470) / p
    [875316569933471522153974751006432883, 763502885943773428587489873304238670, 245525173920460838809518024923471804, 1331450858047352741966030763459774]
  }

  fn modulus_bits() -> u64 {
    470
  }

  fn mult(a: [Field; 4], b: [Field; 4]) -> ArrayX<Field, 4, 2> {
    karatsuba_mult_4(a, b)
  }
}
