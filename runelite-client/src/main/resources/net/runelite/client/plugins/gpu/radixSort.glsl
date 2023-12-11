#include version_header
#include thread_config

#define BITS_PER_PASS 8
#define NUM_BUCKETS (1 << BITS_PER_PASS)

uniform int numItems;

layout(std430, binding = 0) buffer _arr {
  int arr[];
};

layout(std430, binding = 1) buffer _temp {
  int temp_arr[];
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
            if (gl_WorkGroupID.x == 0) {
                globalBuckets[gl_LocalInvocationID.x] = 0;
            }
        
            memoryBarrier();
            barrier();

            // Count number of occurrences of the digit
            int digit = (arr[gl_GlobalInvocationID.x] >> (bit * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
            atomicAdd(globalBuckets[digit], 1);

            memoryBarrier();
            barrier();

            // TODO: Split this up into multiple shaders. Apparently barrier() doesn't sync multiple groups
            // So after the add here the other group could be late and still be adding while we're doing prefix sum stuff
            // So:
            // 1. Everything atomic adds to the buckets
            // 2. One work group calculates the prefix sum
            // 2.5 that same group converets to exclusive
            // 3. read from source and write to dest based on atomic added index and digit

            // Convert the buckets to an inlcusive prefix sum
            // Which gives us the offset to start writing that digit at
            if (gl_WorkGroupID.x == 0) {
                for (int stride = 1; stride < NUM_BUCKETS; stride *= 2) {
                    // TODO: if less than num items 
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


            if (gl_WorkGroupID.x == 0) { // TODO: if global less than num items
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
                temp_arr[gl_GlobalInvocationID.x] = globalBuckets[gl_GlobalInvocationID.x];
            } else {
                temp_arr[gl_GlobalInvocationID.x] = -1;
            }
            return;/*/

            // Note: We add the previous work group's sum to the local sums, making them now a global exclusive scan
            uint index = atomicAdd(globalBuckets[digit], 1);
            int d = arr[gl_GlobalInvocationID.x];

            memoryBarrier(); // Wait so everyone grabs the value they want to write, and then we write all at once after that so no one tramples over another thread's value
            barrier();
            
            // TODO: Can't we just barrier here so everyone gets their data? then overwrite? Gets rid of the need for a temp buffer

            memoryBarrier(); // Wait so everyone grabs the value they want to write, and then we write all at once after that so no one tramples over another thread's value
            barrier();

            temp_arr[index] = d;

            memoryBarrier();
            barrier();
            

            temp_arr[gl_GlobalInvocationID.x] = numItems;

            memoryBarrier();
            barrier();
            return; /*

            pullFromArr = !pullFromArr; // Swap buffers*/
        }
    }

    // NOTE: arr will be the sorted result
}