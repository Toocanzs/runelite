#include version_header
#include thread_config

#define BITS_PER_PASS 8
#define NUM_BUCKETS (1 << BITS_PER_PASS)

uniform int numItems;

layout(std430, binding = 0) buffer _arr {
  int arr[];
};

layout(std430, binding = 3) buffer _globalBuckets {
  int globalBuckets[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    bool pullFromArr = true;
    if (gl_GlobalInvocationID.x < numItems) {
        /*for (int bit = 0; bit < 32/BITS_PER_PASS; bit++)*/
        int bit = 0; {
            globalBuckets[gl_LocalInvocationID.x] = 0;
        
            memoryBarrier();
            barrier();

            // Count number of occurrences of the digit
            int digit = (arr[gl_GlobalInvocationID.x] >> (bit * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(globalBuckets[digit], 1);

            memoryBarrier();
            barrier();

            // Convert the buckets to an inlcusive prefix sum
            // Which gives us the offset to start writing that digit at
            if (gl_WorkGroupID.x == 0) {
                for (int stride = 1; stride < NUM_BUCKETS; stride *= 2) {
                    memoryBarrier();
                    barrier();
                    int temp = 0;
                    if (gl_LocalInvocationID.x >= stride) {
                        temp = globalBuckets[gl_LocalInvocationID.x - stride];
                    }
                    memoryBarrier();
                    barrier();
                    atomicAdd(globalBuckets[gl_LocalInvocationID.x], temp);
                }
            }

            memoryBarrier();
            barrier();

            if (gl_WorkGroupID.x == 0) {
                // Convert from inclusive to exclusive prefix sum by shifting to the right and inserting zero at beginning
                int value = 0;
                if (gl_LocalInvocationID.x > 0) {
                    value = globalBuckets[gl_LocalInvocationID.x - 1];
                }

                memoryBarrier(); // TODO: Not needed cause single work group?
                barrier();

                globalBuckets[gl_LocalInvocationID.x] = value;
            }

            
            memoryBarrier();
            barrier();
            /*if (gl_GlobalInvocationID.x < NUM_BUCKETS) {
                arr[gl_GlobalInvocationID.x] = globalBuckets[gl_GlobalInvocationID.x];
            } else {
                arr[gl_GlobalInvocationID.x] = -1;
            }
            return;/*/

            // Note: We add the previous work group's sum to the local sums, making them now a global exclusive scan
            uint index = atomicAdd(globalBuckets[digit], 1);

            int d = arr[gl_GlobalInvocationID.x];
            // TODO: Can't we just barrier here so everyone gets their data? then overwrite? Gets rid of the need for a temp buffer

            memoryBarrier(); // Wait so everyone grabs the value they want to write, and then we write all at once after that so no one tramples over another thread's value
            barrier();

            arr[index] = d;

            memoryBarrier();
            barrier();

            pullFromArr = !pullFromArr; // Swap buffers*/
        }
    }

    // NOTE: arr will be the sorted result
}