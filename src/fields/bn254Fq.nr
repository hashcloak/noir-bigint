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

struct BNParams {}
impl BigNumParamsTrait<3> for BNParams {
    fn redc_param() -> [Field; 3] {
        [
            0x000000000000000000000000000000000059785d9f353021bcebb62866fe4394, 0x0000000000000000000000000000000000d18988e8129eac1d2961a01cc04eba, 0x0000000000000000000000000000000000000000000000000000000000015291
        ]
    }
    fn modulus() -> [Field; 3] {
        [
            0x0000000000000000000000000000000000816a916871ca8d3c208c16d87cfd47, 0x00000000000000000000000000000000004e72e131a029b85045b68181585d97, 0x0000000000000000000000000000000000000000000000000000000000003064
        ]
    }
    fn double_modulus() -> [Field; 3] {
        [
            0x000000000000000000000000000000000002d522d0e3951a7841182db0f9fa8e, 0x00000000000000000000000000000000009ce5c263405370a08b6d0302b0bb2f, 0x00000000000000000000000000000000000000000000000000000000000060c8
        ]
    }
    fn k() -> u64 {
        255
    }
    fn modulus_bits() -> u64 {
        254
    }
}
