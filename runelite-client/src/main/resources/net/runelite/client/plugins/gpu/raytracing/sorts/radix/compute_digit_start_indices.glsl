#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)

layout(std430, binding = 0) restrict buffer _output {
    uint digit_start_indices[32/BITS_PER_PASS][NUM_BUCKETS];
};

// Call with glDispatch(1,1,1)
layout(local_size_x = THREAD_COUNT) in;
void main() {
    // If we take our digit counts and perform an exclusive prefix sum on it
    // that will give us an array where each element arr[digit] tells us where to _start_ placing those digits
    // It's important to note that this doesn't tell you where to place the digit exactly, just where that run of digits starts
    // That's why we need digit offsets
    // So our final index for any particular element will be digit_start_indices[digit] + digit_offset[digit][i]

    // The prefix sum is so small that we just calculate it sequentially for each pass
    uint pass_number = gl_LocalInvocationID.x; // group size == 32/BITS_PER_PASS so no need to check if in bounds
    uint sum = 0;
    for (int i = 0; i < NUM_BUCKETS; i++) {
        uint c = digit_start_indices[pass_number][i];
        digit_start_indices[pass_number][i] = sum;
        sum += c;
    }
}