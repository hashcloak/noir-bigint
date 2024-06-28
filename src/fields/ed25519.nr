use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::mul::schoolbook_mult;
use crate::utils::arrayX::ArrayX;

struct Ed25519Params {}
// https://neuromancer.sk/std/other/Ed25519
impl BigNumParamsTrait<3> for Ed25519Params {
    // p = 57896044618658097711785492504343953926634992332820282019728792003956564819949
    fn modulus() -> [Field; 3] { 
        [1329227995784915872903807060280344557, 1329227995784915872903807060280344575, 32767]
    }

    fn double_modulus() -> [Field; 3] {
        [1329227995784915872903807060280344538, 1329227995784915872903807060280344575, 65535]
    }

    fn redc_param() -> [Field; 3] {
      // floor(2^(2*255) / p)
      // 57896044618658097711785492504343953926634992332820282019728792003956564819987
      [19, 0, 32768]
    }

    fn k() -> u64 {
        255
    }

    fn modulus_bits() -> u64 {
        255
    }

    fn mult(a: [Field; 3], b: [Field; 3]) -> ArrayX<Field, 3, 2> {
        schoolbook_mult(a,b)
    }
}
