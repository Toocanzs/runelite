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

layout(std430, binding = 3) restrict buffer _control {
    volatile uint block_counter;
    volatile uint status_and_sum[];/*[NUM_BLOCKS][NUM_BUCKETS]*/
};

layout(std430, binding = 4) restrict readonly buffer _digit_start_indices {
    uint digit_start_indices[32/BITS_PER_PASS][NUM_BUCKETS];
};
#define STATUS_BITMASK 0xc0000000
#define STATUS_BITSHIFT 30
#define GET_STATUS(x) ((x & STATUS_BITMASK) >> STATUS_BITSHIFT)

#define STATUS_PARTIAL_SUM_BIT 0x40000000
#define STATUS_GLOBAL_SUM_BIT  0x80000000
#define STATUS_VALUE_BITMASK   0x3fffffff

shared uint group_block_id; // TODO: If we hit the shared storage limit, this can be stored in digit offsets temporarily (must barrier zeroing)
shared uint digit_offsets[NUM_BUCKETS][THREAD_COUNT];
#define SPIN_WHILE(value_to_write_to, value_to_read_from, condition) \
    do {\
        value_to_write_to = atomicCompSwap(value_to_read_from, 0, 0);\
    } while ((condition));

#define SPIN_WHILE_ZERO(value_to_write_to, value_to_read_from) \
    do {\
        value_to_write_to = atomicCompSwap(value_to_read_from, 0, 0);\
    } while (value_to_write_to == 0);

layout(local_size_x = THREAD_COUNT) in;
void main() {
    // One thread grabs the next block by incrementing the block counter
    if (gl_LocalInvocationID.x == 0) {
        // Written to shared memory so everyone can see which block they're in
        group_block_id = atomicAdd(block_counter, 1);
    }
    barrier();

    uint block_id = group_block_id;
    uint block_size = gl_WorkGroupSize.x;
    uint block_start_index = block_id * block_size;
    uint block_local_index = gl_LocalInvocationID.x;
    uint input_array_index = block_start_index + block_local_index;
    for (int i = 0; i < block_size; i++) {
        digit_offsets[i][block_local_index] = 0;
    }

    if (input_array_index < num_items) {
        uint input_key = source_keys[input_array_index];
        uint value = values[input_key];
        uint digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        uint digit_start_index = digit_start_indices[pass_number][digit];
        memoryBarrier();
        barrier();

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
        uint digit_offset = block_local_index == 0 ? 0 : digit_offsets[digit][block_local_index - 1];

        if (block_local_index < NUM_BUCKETS) {
            uint bucket_index = block_local_index;
            // Write out the digit sum (local sum of this block) so other blocks can see it
            uint bit = block_id == 0 ? STATUS_GLOBAL_SUM_BIT : STATUS_PARTIAL_SUM_BIT; // Note that the first block can only be a global sum (also we depend on that being the case later)
            uint sum = digit_offsets[bucket_index][block_size-1]; // Last element of inclusive prefix sum is the total sum
            uint value = (sum & STATUS_VALUE_BITMASK) | bit;
            atomicExchange(status_and_sum[block_id * NUM_BUCKETS + bucket_index], value);
        }

        // Decoupled lookback
        // Basically we want to know the total sum of from blocks before us,
        // But we don't want to wait for that information to sequentially go down the chain of blocks
        // So we look back and add partial sums up until we reach a global sum, and that global sum represents the sum to the left of that block (including that block's sum)
        if (block_id != 0) {
            uint previous_digit_sum = 0;
            if (block_local_index < NUM_BUCKETS) {
                uint bucket_index = block_local_index;
                uint previous_block_id = block_id - 1;
                while (true) {
                    // NOTE: For block 0 we depend on it never writing a partial sum. If it didn't do that this would loop forever
                    uint control_value;
                    SPIN_WHILE_ZERO(control_value, status_and_sum[previous_block_id * NUM_BUCKETS + bucket_index]);

                    if ((control_value & STATUS_GLOBAL_SUM_BIT) != 0) {
                        previous_digit_sum += control_value & STATUS_VALUE_BITMASK;
                        break;
                    }
                    if ((control_value & STATUS_PARTIAL_SUM_BIT) != 0) {
                        previous_digit_sum += control_value & STATUS_VALUE_BITMASK;
                        previous_block_id = previous_block_id == 0 ? 0 : (previous_block_id - 1);
                    }
                }
                // Write out the global sum now that we know it
                uint total_sum = digit_offsets[bucket_index][block_size-1] + previous_digit_sum;
                atomicExchange(status_and_sum[block_id * NUM_BUCKETS + bucket_index], (total_sum & STATUS_VALUE_BITMASK) | STATUS_GLOBAL_SUM_BIT);
            }
        }
        barrier();
        
        uint previous_block_digit_offset_sum = 0;
        if (block_id != 0) {
            // Note: We spin here instead of storing the total sum at index [digit] from the previous loop because the last block might not have enough threads to gather that digit
            // For example if N=257, the last block has 1 thread so unless the digit is 0, it won't ever be gotten in the above loop
            uint control_value;
            SPIN_WHILE(control_value, status_and_sum[(block_id-1) * NUM_BUCKETS + digit], (control_value & STATUS_GLOBAL_SUM_BIT) == 0);
            previous_block_digit_offset_sum = control_value & STATUS_VALUE_BITMASK;
            
        }

        uint output_index = digit_start_index + digit_offset + previous_block_digit_offset_sum;
        destination_keys[output_index] = input_key;
    }
}