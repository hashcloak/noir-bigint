use crate::utils::arrayX::ArrayX;
use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::bignum_test::{
    test_mul, test_add, test_div, test_invmod, assert_is_not_equal, assert_is_not_equal_fail,
    assert_is_not_equal_overloaded_lhs_fail, assert_is_not_equal_overloaded_rhs_fail,
    assert_is_not_equal_overloaded_fail
};
use crate::mul::schoolbook_mult;

struct Test230NonPrimeParams {}

impl BigNumParamsTrait<2> for Test230NonPrimeParams {
  // p = 89765080534193171421762193315137106136271007783279660372993028469684
  fn modulus() -> [Field; 2] {
    [0x94e89ef3fba74a9314e05b5d1533b4, 0x0003545ed2c21e1cee7ff12c1f985d]
  }

  fn double_modulus() -> [Field; 2] {
    [0x29d13de7f74e952629c0b6ba2a6768, 0x0006a8bda5843c39dcffe2583f30bb]
  }

  fn redc_param() -> [Field; 2] {
     [71101653383256209887574331950655516, 49902361338040446869900031859956312]
  }

  fn modulus_bits() -> u64 {
    230 
  }

  fn mult(a: [Field; 2], b: [Field; 2]) -> ArrayX<Field, 2, 2> {
    schoolbook_mult(a,b)
  }
}
