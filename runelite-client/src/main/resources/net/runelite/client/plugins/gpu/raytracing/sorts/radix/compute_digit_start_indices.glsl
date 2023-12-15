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
    if (gl_GlobalInvocationID.x < num_items) {
        for (uint pass_number = 0; pass_number < (32/BITS_PER_PASS); pass_number++) {
            digit_start_indices[pass_number][gl_LocalInvocationID.x] = 0;
        }
        memoryBarrier();
        barrier();

        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        // Note that `digit_start_indices` is currently just a count of digits, we'll calculate the start indices later
        for (uint pass_number = 0; pass_number < (32/BITS_PER_PASS); pass_number++) {
            uint value = values[keys[gl_GlobalInvocationID.x]];
            uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(digit_start_indices[pass_number][digit], 1);
        }
        memoryBarrier();
        barrier();

        // If we take our digit counts and perform an exclusive prefix sum on it
        // that will give us an array where each element arr[digit] tells us where to _start_ placing those digits
        // It's important to note that this doesn't tell you where to place the digit exactly, just where that run of digits starts
        // That's why we need digit offsets
        // So our final index for any particular element will be digit_start_indices[digit] + digit_offset[digit][i]

        // One group calculates the prefix sums
        if (gl_WorkGroupID.x == 0) { 
            if (gl_LocalInvocationID.x < (32/BITS_PER_PASS)) { // TODO: If we do bits_per_pass == 8, this probably should be not single threaded
                // This one is so small that we just calculate it on one thread
                uint sum = 0;
                for (int i = 0; i < NUM_BUCKETS; i++) {
                    uint c = digit_start_indices[gl_LocalInvocationID.x][i];
                    digit_start_indices[gl_LocalInvocationID.x][i] = sum;
                    sum += c;
                }
            }
        }
    }
}