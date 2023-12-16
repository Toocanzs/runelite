#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)

uniform uint num_items;

layout(std430, binding = 0) restrict readonly buffer _values {
    uint values[];
};

layout(std430, binding = 1) restrict readonly buffer _keys {
    uint keys[];
};

layout(std430, binding = 2) restrict buffer _output {
    uint digit_start_indices[32/BITS_PER_PASS][NUM_BUCKETS];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_items) { // TODO: 2d group size so we can go over 65k blocks on x
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        // Note that `digit_start_indices` is currently just a count of digits, we'll calculate the start indices later
        uint value = values[keys[gl_GlobalInvocationID.x]];
        for (uint pass_number = 0; pass_number < (32/BITS_PER_PASS); pass_number++) {
            uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(digit_start_indices[pass_number][digit], 1);
        }
    }
}