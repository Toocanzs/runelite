#include version_header
#include thread_config

#define BITS_PER_PASS 8
#define NUM_BUCKETS (1 << BITS_PER_PASS)

shared int localBuckets[NUM_BUCKETS];

uniform int numItems;

layout(std430, binding = 0) buffer _arr {
  int arr[];
};

layout(std430, binding = 1) buffer _temp {
  int temp_arr[];
};

layout(std430, binding = 2) buffer _groupSums {
  int groupSums[];
};

#define GET_DATA(x) (pullFromArr ? arr[(x)] : temp_arr[(x)])
#define STORE_DATA(x, y) if (pullFromArr) temp_arr[(x)] = (y); else arr[(x)] = (y);

layout(local_size_x = THREAD_COUNT) in;
void main() {
    bool pullFromArr = true;
    if (gl_GlobalInvocationID.x < numItems) {
        /*for (int bit = 0; bit < 32/BITS_PER_PASS; bit++)*/
        int bit = 0; {
            // Set counts to 0
            localBuckets[gl_LocalInvocationID.x] = 0;
        
            memoryBarrierShared();
            barrier();

            // Count number of occurrences of the digit
            int digit = (GET_DATA(gl_GlobalInvocationID.x) >> (bit * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(localBuckets[digit], 1);

            memoryBarrierShared(); // TODO: Remove. for loop has one
            barrier();

            // Convert the buckets to an inlcusive prefix sum
            // Which gives us the offset to start writing that digit at
            for (int stride = 1; stride < THREAD_COUNT; stride *= 2) {
                memoryBarrierShared();
                barrier();
                int temp = 0;
                if (gl_LocalInvocationID.x >= stride) {
                    temp = localBuckets[gl_LocalInvocationID.x - stride];
                }
                memoryBarrierShared();
                barrier();
                atomicAdd(localBuckets[gl_LocalInvocationID.x], temp);
            }

            memoryBarrierShared();
            barrier();

            // Convert from inclusive to exclusive prefix sum by shifting to the right and inserting zero at beginning
            if (localBuckets[gl_LocalInvocationID.x] > 0) {
                localBuckets[gl_LocalInvocationID.x] = localBuckets[gl_LocalInvocationID.x - 1];
            } else {
                localBuckets[gl_LocalInvocationID.x] = 0;
            }

            memoryBarrierShared();
            barrier();

            uint previousGroupSum = gl_WorkGroupID.x * gl_WorkGroupSize.x; // Counting digits for an array of size N will always produce N as the group count
            localBuckets[gl_LocalInvocationID.x] += int(previousGroupSum);

            memoryBarrierShared();
            barrier();

            // Note: We add the previous work group's sum to the local sums, making them now a global exclusive scan
            uint index = atomicAdd(localBuckets[digit], 1);

            int d = GET_DATA(gl_GlobalInvocationID.x);
            STORE_DATA(index, d);

            memoryBarrier(); // Note we use a non-shared one because dest is global memory
            barrier();

            pullFromArr = !pullFromArr; // Swap buffers*/
        }
    }

    // NOTE: arr will be the sorted result
}