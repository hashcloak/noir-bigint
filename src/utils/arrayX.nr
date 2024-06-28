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

use dep::std;

/**
 * @brief Array abstraction, whose size is a known multiplier `SizeMultiplier` of an initial size `N`
 *
 * @note ArrayX is a workaround for the lack of arithmetic over generics.
 *       e.g. [Field; N * 2] is not currently possible
 *       This abstraction can be removed once Noir supports arithmetic on generics.
**/
struct ArrayX<T, let N: u64, let SizeMultiplier: u8> {
    segments: [[T; N]; SizeMultiplier]
}

impl<T, let N: u64, let SizeMultiplier: u8> std::convert::From<[T; N]> for ArrayX<T, N, SizeMultiplier> where T: std::default::Default { 
    fn from(input: [T; N]) -> Self {
        assert(N == 1);
        let mut result = ArrayX::new();
        result.segments[0] = input;
        result
    }
}

impl<T, let N: u64, let SizeMultiplier: u8> std::convert::From<[[T; N]; SizeMultiplier]> for ArrayX<T, N, SizeMultiplier> where T: std::default::Default { 
    fn from(input: [[T; N]; SizeMultiplier]) -> Self {
        ArrayX{ segments: input }
    }
}

impl<T, let N: u64, let SizeMultiplier: u8> std::cmp::Eq for ArrayX<T, N, SizeMultiplier> where T: std::cmp::Eq { 
    fn eq(self, other: Self) -> bool {
        let mut result: bool = true;
        for i in 0..SizeMultiplier {
            for j in 0..N {
                result = result & (self.segments[i][j] == other.segments[i][j]);
            }
        }
        result
    }
}

impl<T, let N: u64, let SizeMultiplier: u8> ArrayX<T, N, SizeMultiplier> {

    fn new() -> Self where T: std::default::Default {
        ArrayX { segments: [[T::default(); N]; SizeMultiplier] }
    }

    fn mul_assign(&mut self, i: u64, rhs: T) where T: std::ops::Mul {
        let segment = i / N;
        let index = i % N;
        self.segments[segment][index] *= rhs;
    }

    fn add_assign(&mut self, i: u64, rhs: T) where T: std::ops::Add {
        let segment = i / N;
        let index = i % N;
        self.segments[segment][index] += rhs;
    }

    fn sub_assign(&mut self, i: u64, rhs: T) where T: std::ops::Sub {
        let segment = i / N;
        let index = i % N;
        self.segments[segment][index] -= rhs;
    }

    fn set(&mut self, i: u64, x: T) {
        let segment = i / N;
        let index = i % N;
        self.segments[segment][index] = x;
    }

    fn get(self, i: u64) -> T {
        let segment = i / N;
        let index = i % N;
        self.segments[segment][index]
    }
}
