# PariGP scripts to support testing/usage

## Generating parameters for BigNumParamsTrait

### 1. Generate random modulus for bitlength

For example, generate a random modulus `p` of 256 bits. 
```
bits = 256;
random(2^bits)
```

### 2. Convert to radix-2^120

Convert a number to an array of the radix-2^120 representation. 
```
convert_to_radix_120(number) = {
  local(radix_120_array, base, quotient, remainder);
  radix_120_array = [];
  base = 2^120;
  quotient = number;
  while(quotient > 0,
    remainder = quotient % base;
    quotient = quotient \ base;
    radix_120_array = concat(radix_120_array, [remainder]);
  );
  return (radix_120_array);
}
```

Convert it to radix-2^120 and print as hex values:
```
convert_to_radix_120(number) = {
  local(radix_120_array, base, quotient, remainder);
  radix_120_array = [];
  base = 2^120;
  quotient = number;
  while(quotient > 0,
    remainder = quotient % base;
    quotient = quotient \ base;
    radix_120_array = concat(radix_120_array, [remainder]);
  );
  print(vector(#radix_120_array, i, printf("0x%030x", radix_120_array[i])));
}
```

### 3. Calculate redc parameter

For bitlength `k` of `p`, the Barrett reduction parameter `redc = floor(2^2*(k+1)/ p)`.

## Convert coefficient array to number
Convert array into corresponding number.
`[a0, a1, a2, a3]` equals `a0 + a1* 2^120 + a2 * 2^240 + a3 * 2^360`
```
array_to_number(limbs) = {
    my(num = 0);
    for (i = 1, #limbs,
        num += limbs[i] * 2^((i-1) * 120);
    );
    num;
}
```

If you have coefficient array `[1, 2, 3, 4]`, this equals the number `1+ 2*2^120 + 3*2^240 + 4*2^360`. 
Print:
```
1+ 2*2^120 + 3*2^240 + 4*2^360
```
and seperately:
```
array_to_number([1, 2, 3, 4])
```
They should be equal. 

Another example. The max size of coefficient is 120 bits. Max value is `2^120 -1` = `0xffffffffffffffffffffffffffffff`. The number represented by array of 4x the max coefficient is 
```
(2^120 -1)+ (2^120 -1)*2^120 + (2^120 -1)*2^240 + (2^120 -1)*2^360. 
```
Compare that with:
```
array_to_number([0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff])
```

## Schoolbook

Compare the multiplication in PariGP
```
a = array_to_number([0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff]);
b = array_to_number([0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff]);
a*b
# = 3121748550315992231381597229793166305748598142664971150859156959625371735286071490563537443896896969673989899466438829144210059436075882721050625
```
...with the resulting limbs from the Noir function:
```
# 0xfffffffffffffffffffffffffffffe000000000000000000000000000001
# 0x01fffffffffffffffffffffffffffffc000000000000000000000000000002
# 0xfffffffffffffffffffffffffffffe000000000000000000000000000001
    
array_to_number([0xfffffffffffffffffffffffffffffe000000000000000000000000000001,0x01fffffffffffffffffffffffffffffc000000000000000000000000000002,0xfffffffffffffffffffffffffffffe000000000000000000000000000001])
# = 3121748550315992231381597229793166305748598142664971150859156959625371735286071490563537443896896969673989899466438829144210059436075882721050625
# Correct!
```
Note that the limbs of the result from Noir are not necessarily smaller than 120 bits. This is why converting the resulting number back to the coefficient array in PariGP won't give the same answer. 
