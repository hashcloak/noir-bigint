use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::mul::schoolbook_mult;
use crate::utils::arrayX::ArrayX;

struct Secp256k1Params {}
// https://neuromancer.sk/std/secg/secp256k1
impl BigNumParamsTrait<3> for Secp256k1Params {
    // p = 115792089237316195423570985008687907853269984665640564039457584007908834671663
    fn modulus() -> [Field; 3] { 
        [1329227995784915872903807055985376303, 1329227995784915872903807060280344575, 65535]
    }

    fn double_modulus() -> [Field; 3] {
        [1329227995784915872903807051690408030, 1329227995784915872903807060280344575, 131071]
    }

    fn redc_param() -> [Field; 3] {
      // floor(2^(2*256) / p)
      // 115792089237316195423570985008687907853269984665640564039457584007917424608209
      [4294968273, 0, 65536]
    }

    fn modulus_bits() -> u64 {
        256
    }

    fn mult(a: [Field; 3], b: [Field; 3]) -> ArrayX<Field, 3, 2> {
        schoolbook_mult(a,b)
    }
}
