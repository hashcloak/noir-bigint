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

// Decomposes a single field into two 120 bit fields and a carry
unconstrained pub fn split_120_bits(x: Field) -> (Field, Field) {
    let x_bytes: [u8] = x.to_le_bytes(32);

    let mut low: Field = 0;
    let mut high: Field = 0;

    comptime let offsets: [Field; 16] = [
        1, 0x100, 0x10000, 0x1000000, 0x100000000, 0x10000000000, 0x1000000000000, 0x100000000000000, 0x10000000000000000, 0x1000000000000000000, 0x100000000000000000000, 0x10000000000000000000000, 0x1000000000000000000000000, 0x100000000000000000000000000, 0x10000000000000000000000000000, 0x1000000000000000000000000000000
    ];

    for i in 0..15 {
        low += (x_bytes[i] as Field) * offsets[i];
        high += (x_bytes[i + 15] as Field) * offsets[i];
    }
    high += (x_bytes[30] as Field) * offsets[15];
    assert(x_bytes[31] == 0);
    (low, high)
}

/**
 * @brief Decomposes a single field into two 60 bit fields
 *
 * @description Expects the input limb to be in the range [0, ..., 2^{120 - 1}]
 **/
unconstrained pub fn split_60_bits(x: Field) -> (u64, u64) {
    let x_bytes = x.to_le_bytes(32);

    let mut low: u64 = 0;
    let mut high: u64 = 0;

    comptime let offsets: [u64; 8] = [1, 0x100, 0x10000, 0x1000000, 0x100000000, 0x10000000000, 0x1000000000000, 0x100000000000000];
    for i in 0..8 {
        low += (x_bytes[i] as u64) * offsets[i];
        high += (x_bytes[i + 8] as u64) * offsets[i];
    }
    let t1 = low >> 60;
    let mask = ((1 as u64) << 60 as u8) - 1;
    low = low & mask;
    high = (high << 4) | t1;
    (low, high)
}
