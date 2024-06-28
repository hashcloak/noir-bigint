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

use crate::BigNum;
use crate::BigNumParamsTrait;
use crate::mul::schoolbook_mult;
use crate::utils::arrayX::ArrayX;

struct BNParams {}
impl BigNumParamsTrait<3> for BNParams {
  // floor(2^(2*255) / p) = 153139381818454018477577869068761289265822928212768026270393311338486818554772
  // Note that this use modulus_bits+1 instead of modulus_bits. Is this needed?
    fn redc_param() -> [Field; 3] { // 153139381818454018477577869068761289265822928212768026270393311338486818554772
        [
            0x000000000000000000000000000000000059785d9f353021bcebb62866fe4394, 0x0000000000000000000000000000000000d18988e8129eac1d2961a01cc04eba, 0x0000000000000000000000000000000000000000000000000000000000015291
        ]
    }
    fn modulus() -> [Field; 3] { // 21888242871839275222246405745257275088696311157297823662689037894645226208583
        [
            0x0000000000000000000000000000000000816a916871ca8d3c208c16d87cfd47, 0x00000000000000000000000000000000004e72e131a029b85045b68181585d97, 0x0000000000000000000000000000000000000000000000000000000000003064
        ]
    }
    fn double_modulus() -> [Field; 3] { // 43776485743678550444492811490514550177392622314595647325378075789290452417166
        [
            0x000000000000000000000000000000000002d522d0e3951a7841182db0f9fa8e, 0x00000000000000000000000000000000009ce5c263405370a08b6d0302b0bb2f, 0x00000000000000000000000000000000000000000000000000000000000060c8
        ]
    }
    
    fn modulus_bits() -> u64 {
        254
    }

    fn mult(a: [Field; 3], b: [Field; 3]) -> ArrayX<Field, 3, 2> {
        schoolbook_mult(a,b)
    }
}
