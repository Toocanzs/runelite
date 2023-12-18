#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)
#define NUM_PASSES (32/BITS_PER_PASS)

uniform uint num_items;

layout(std430, binding = 0) restrict readonly buffer _values {
    uint values[];
};

layout(std430, binding = 1) restrict readonly buffer _keys {
    uint keys[];
};

layout(std430, binding = 2) restrict buffer _output {
    uint digit_counts[NUM_PASSES][NUM_BUCKETS];
};

shared uint shared_digit_counts[NUM_PASSES][NUM_BUCKETS];

layout(local_size_x = THREAD_COUNT) in;
void main() {

    if (gl_GlobalInvocationID.x < num_items) { // TODO: 2d group size so we can go over 65k blocks on x
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        uint value = values[keys[gl_GlobalInvocationID.x]];
        for (uint pass_number = 0; pass_number < (32/BITS_PER_PASS); pass_number++) {
            uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(digit_counts[pass_number][digit], 1);
        }
    }

    /*
    // TODO: this is faster, but totally wrong atm
    if (gl_GlobalInvocationID.x < num_items) { // TODO: 2d group size so we can go over 65k blocks on x
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        uint value = values[keys[gl_GlobalInvocationID.x]];
        for (uint pass_number = 0; pass_number < (32/BITS_PER_PASS); pass_number++) {
            uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(shared_digit_counts[pass_number][digit], 1);
        }
    }

    barrier();
    // Write local counts to global memory
    // It's done this way to keep the number of writes to global memory constant
    // For example if N=256 and every digit was a 0, we'd be adding 256 times to global memory, but under this scheme we add 256 times to the faster shared memory, 
    // and then just once for the 0th digit count to global memory. Amounted to a ~1ms speed up at 1 million items (2.36ms vs 1.46ms) at the time of writing
    if (gl_LocalInvocationID.x < NUM_BUCKETS*NUM_PASSES) { // Assumes THREAD_COUNT > NUM_BUCKETS*NUM_PASSES
        uint bucket_index = gl_LocalInvocationID.x % NUM_BUCKETS;
        uint pass_number = gl_LocalInvocationID.x / NUM_BUCKETS;

        if (shared_digit_counts[pass_number][gl_LocalInvocationID.x] > 0) {
            atomicAdd(digit_counts[pass_number][gl_LocalInvocationID.x], shared_digit_counts[pass_number][gl_LocalInvocationID.x]);
        }
    }*/
}