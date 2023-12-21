#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)

layout(std430, binding = 0) restrict buffer _output {
    uint digit_start_indices[32/BITS_PER_PASS][NUM_BUCKETS];
};

// Call with glDispatch(1,numPasses,1)
layout(local_size_x = THREAD_COUNT) in;
void main() {
    // If we take our digit counts and perform an exclusive prefix sum on it
    // that will give us an array where each element arr[digit] tells us where to _start_ placing those digits
    // It's important to note that this doesn't tell you where to place the digit exactly, just where that run of digits starts
    // That's why we need digit offsets
    // So our final index for any particular element will be digit_start_indices[digit] + digit_offset[digit][i]

    uint pass_number = gl_WorkGroupID.y; 
    uint bucket_index = gl_LocalInvocationID.x;

    // Hillis & Steele inclusive scan
    for (uint stride = 1; stride < NUM_BUCKETS; stride <<= 1) {
        uint temp = bucket_index >= stride ? digit_start_indices[pass_number][bucket_index - stride] : 0;
        groupMemoryBarrier();
        barrier();
        digit_start_indices[pass_number][bucket_index] += temp;
        groupMemoryBarrier();
        barrier();
    }

    // Convert to exclusive by shifting over 1 to the right, and inserting a zero at the start
    uint temp = 0;
    if (bucket_index > 0) {
        temp =  digit_start_indices[pass_number][bucket_index - 1];
    }
    groupMemoryBarrier();
    barrier();
    digit_start_indices[pass_number][bucket_index] = temp;
}