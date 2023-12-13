#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)

uniform uint num_items;
uniform uint pass_number;

layout(std430, binding = 0) readonly buffer _values {
  uint values[];
};

layout(std430, binding = 1) readonly buffer _source_keys {
  uint source_keys[];
};

layout(std430, binding = 2) writeonly buffer _destination_keys {
  uint destination_keys[];
};

shared uint digit_counts[NUM_BUCKETS];
shared uint digit_offsets[NUM_BUCKETS][THREAD_COUNT];

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_items) {

        digit_counts[gl_LocalInvocationID.x] = 0;
        for (int i = 0; i < THREAD_COUNT; i++) {
            digit_offsets[i][gl_LocalInvocationID.x] = 0;
        }

        barrier();
        
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        uint value = values[source_keys[gl_GlobalInvocationID.x]];
        uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        atomicAdd(digit_counts[digit], 1);

        // digit_offsets is eventually going to tell us how much to offset this digit by to maintain the order
        // that the items appeared in in the original array (making it a so-called "stable" sort)
        // In order to generate that offset table, we would need to know exactly how many instances of the digit we want to place
        // have appeared before us in the input array
        // so for example if we have an array like the following
        // [2,1,1,3,1,2,1,4]
        // You can see we have multiple 1s in that array. The order they appear in that array needs to be maintained
        // (because it might not just be a 1, it might be a 1 in the bottom N bits, with other bits to be sorted by later)
        // so giving just the 1s a letter to distinguish them
        // [2,A1,B1,3,C1,2,D1,4]
        // Now our output array should contain 
        // [A1, B1, C1, D1, 2, 2, 3, 4]
        // The order they appeared in is maintained
        // To get that we can generate a binary 1 or 0 for every digit, across every data element indicating whether or not the current element has that digit
        // Or in other words, for digit 1 that array would be
        // 2  -> 0
        // A1 -> 1
        // B1 -> 1
        // 3  -> 0
        // C1 -> 1
        // 2  -> 0
        // D1 -> 1
        // 4  -> 0
        // And that's what the following line is doing.
        digit_offsets[digit][gl_LocalInvocationID.x] = 1;
        barrier();

        // Now that we have that binary 1 or 0 for each digit in the input array,
        // We can perform an exclusive prefix sum to get the relative offset of that digit
        // Meaning our result will map
        // A1 -> 0
        // B1 -> 1
        // C1 -> 2
        // D1 -> 3
        // How does that work?
        // Well if we take out previous binary array from above, squished into a single line
        // [0,1,1,0,1,0,1,0]
        // Now we do an exclusive prefix sum giving
        // [0,0,1,2,2,3,3,4]
        // And if you plug in the index of each element
        // A1 = index 1 and prefix[1] = 0
        // B1 = index 2 and prefix[2] = 1
        // C1 = index 4 and prefix[4] = 2
        // D1 = index 6 and prefix[6] = 3
        // Exactly what we wanted.

        // For every digit, compute an exclusive prefix sum across all elements 
        for (int bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
            for (int stride = 1; stride < THREAD_COUNT; stride *= 2) {
                uint digit_offset = 0;
                if (gl_LocalInvocationID.x >= stride) {
                    digit_offset = digit_offsets[bucket_index][gl_LocalInvocationID.x - stride];
                }
                barrier();
                atomicAdd(digit_offsets[bucket_index][gl_LocalInvocationID.x], digit_offset);
                barrier();
            }
            barrier();

            // Convert from inclusive prefix sum to exclusive by shifting to the right one and adding a 0 at the start
            uint digit_offset = 0;
            if (gl_LocalInvocationID.x > 0) {
                digit_offset = digit_offsets[bucket_index][gl_LocalInvocationID.x-1];
            }
            barrier();
            digit_offsets[bucket_index][gl_LocalInvocationID.x] = digit_offset;
            barrier();
        }

        // If we take our digit counts and perform an exclusive prefix sum on it
        // that will give us an array where each element arr[digit] tells us where to *start* placing those digits
        // It's important to note that this doesn't tell you where to place the digit exactly, just where that run of digits starts
        // That's why we need digit offsets
        // So our final index for any particular element will be digit_prefix_sum[digit] + digit_offset[digit][i]
        if (gl_LocalInvocationID.x == 0) {
            // The digit counts array is so small that we will just calculate the prefix sum sequentially on one thread
            uint sum = 0;
            for (int i = 0; i < NUM_BUCKETS; i++) {
                uint c = digit_counts[i];
                digit_counts[i] = sum;
                sum += c;
            }
        }
        barrier();

        uint digit_offset = digit_offsets[digit][gl_LocalInvocationID.x];
        uint index = digit_counts[digit] + digit_offset;

        destination_keys[index] = source_keys[gl_GlobalInvocationID.x];
    }
}