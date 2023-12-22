#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)
#define NUM_PASSES (32/BITS_PER_PASS)

uniform uint num_items;

struct KeyValue {
    uint key;
    uint value;
};

layout(std430, binding = 0) restrict readonly buffer _key_values {
    KeyValue key_values[];
};

layout(std430, binding = 1) restrict buffer _output {
    uint digit_counts[NUM_PASSES][NUM_BUCKETS];
};

shared uint shared_digit_counts[NUM_PASSES][NUM_BUCKETS];

#if NUM_BUCKETS > THREAD_COUNT
#error "Code assumes that NUM_BUCKETS > THREAD_COUNT in every if (block_local_index < NUM_BUCKETS). Must be rewritten if this assumption is broken"
#endif

// call with glDispatchCompute(numBlocks,numPasses,1)
layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_LocalInvocationID.x < NUM_BUCKETS) {
        for (uint pass_number = 0; pass_number < NUM_PASSES; pass_number++) {
            shared_digit_counts[pass_number][gl_LocalInvocationID.x] = 0;
        }
    }

    groupMemoryBarrier();
    barrier();

    if (gl_GlobalInvocationID.x < num_items) { // TODO: 2d group size so we can go over 65k blocks on x
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        uint index = gl_GlobalInvocationID.x;
        uint value = key_values[index].value;
        for (uint pass_number = 0; pass_number < NUM_PASSES; pass_number++) {
            uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(shared_digit_counts[pass_number][digit], 1);
        }
    }

    groupMemoryBarrier();
    barrier();

    // Write local counts to global memory
    // It's done this way to keep the number of writes to global memory constant
    // For example if N=256 and every digit was a 0, we'd be adding 256 times to global memory, but under this scheme we add 256 times to the faster shared memory, 
    // and then just once for the 0th digit count to global memory. Amounted to a ~17% speedup at the time of writing
    if (gl_LocalInvocationID.x < NUM_BUCKETS) {
        uint bucket_index = gl_LocalInvocationID.x;
        for (uint pass_number = 0; pass_number < NUM_PASSES; pass_number++) {
            if (shared_digit_counts[pass_number][gl_LocalInvocationID.x] > 0) {
                atomicAdd(digit_counts[pass_number][bucket_index], shared_digit_counts[pass_number][bucket_index]);
            }
        }
    }
}