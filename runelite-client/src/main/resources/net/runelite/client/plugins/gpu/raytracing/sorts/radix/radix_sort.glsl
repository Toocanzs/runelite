#include version_header
#include thread_config

#define BITS_PER_PASS 4
#define NUM_BUCKETS (1 << BITS_PER_PASS)

uniform uint num_items;
uniform uint pass_number;

layout(std430, binding = 0) restrict readonly buffer _values {
  uint values[];
};

layout(std430, binding = 1) restrict readonly buffer _source_keys {
  uint source_keys[];
};

layout(std430, binding = 2) restrict writeonly buffer _destination_keys {
  uint destination_keys[];
};

layout(std430, binding = 3) restrict volatile coherent buffer _control {
  uint block_counter;
};

shared uint digit_start_indices[NUM_BUCKETS];
shared uint digit_offsets[NUM_BUCKETS][THREAD_COUNT];

layout(local_size_x = THREAD_COUNT) in;
void main() {
    uint block_id = gl_WorkGroupID.x;
    uint block_size = gl_WorkGroupSize.x;
    uint block_start_index = block_id * block_size;
    uint block_local_index = gl_LocalInvocationID.x;
    uint input_array_index = block_start_index + block_local_index;

    if (input_array_index < num_items) {
        digit_start_indices[block_local_index] = 0;
        for (int i = 0; i < block_size; i++) {
            digit_offsets[i][block_local_index] = 0;
        }

        barrier();
        
        // Count number of occurrences of the digit
        // "Digit" doesn't refer to a decimal digit like 1, 10, 100,
        // but rather it's a BITS_PER_PASS bit digit
        // Think of it like a hex digit where each digit represents 0 to 15
        // If BITS_PER_PASS == 4, then it is actually a hex digit
        // Note that `digit_start_indices` is currently just a count of digits, we'll calculate the start indices later
        uint value = values[source_keys[input_array_index]];
        uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        atomicAdd(digit_start_indices[digit], 1);

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
        digit_offsets[digit][block_local_index] = 1;
        barrier();

        // Now that we have that binary 1 or 0 for each digit in the input array,
        // We can perform an exclusive prefix sum to get the relative offset of that digit
        // Meaning our result will map
        // A1 -> 0
        // B1 -> 1
        // C1 -> 2
        // D1 -> 3
        // How does that work?
        // Well if we take out previous binary array from above
        // [0,1,1,0,1,0,1,0]
        // Now we do an exclusive prefix sum giving
        // [0,0,1,2,2,3,3,4]
        // And if you plug in the index of each element
        // A1 = index 1 and prefix[1] = 0
        // B1 = index 2 and prefix[2] = 1
        // C1 = index 4 and prefix[4] = 2
        // D1 = index 6 and prefix[6] = 3
        // Exactly what we wanted.

        // For every bucket, compute an inclusive prefix sum across all elements
        for (uint stride = 1; stride < block_size; stride <<= 1) {
            uint values_to_add[NUM_BUCKETS];
            for (uint bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
                if (block_local_index >= stride) {
                    values_to_add[bucket_index] = digit_offsets[bucket_index][block_local_index - stride];
                } else {
                    values_to_add[bucket_index] = 0;
                }
            }
            barrier();
            for (uint bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
                if (values_to_add[bucket_index] != 0) {
                    atomicAdd(digit_offsets[bucket_index][block_local_index], values_to_add[bucket_index]);
                }
            }
            barrier();
        }
        barrier();

        // Convert to exclusive prefix sum by shifting over to the right and inserting a zero at the start
        for (uint bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
            uint digit_offset = 0;
            if (block_local_index > 0) {
                digit_offset = digit_offsets[bucket_index][block_local_index-1];
            }
            barrier();
            digit_offsets[bucket_index][block_local_index] = digit_offset;
            barrier();
        }
        barrier();

        // If we take our digit counts and perform an exclusive prefix sum on it
        // that will give us an array where each element arr[digit] tells us where to _start_ placing those digits
        // It's important to note that this doesn't tell you where to place the digit exactly, just where that run of digits starts
        // That's why we need digit offsets
        // So our final index for any particular element will be digit_start_indices[digit] + digit_offset[digit][i]
        if (block_local_index == 0) {
            // This one is so small that we just calculate it on one thread
            uint sum = 0;
            for (int i = 0; i < NUM_BUCKETS; i++) {
                uint c = digit_start_indices[i];
                digit_start_indices[i] = sum;
                sum += c;
            }
        }
        barrier();

        uint output_index = digit_start_indices[digit] + digit_offsets[digit][block_local_index];
        destination_keys[output_index] = source_keys[input_array_index];
    }
}