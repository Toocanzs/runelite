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

#define NUM_BITFIELD_INTS (THREAD_COUNT/32)

shared uint group_block_id; // TODO: If we hit the shared storage limit, this can be stored in digit offsets temporarily (must barrier zeroing)
shared uint digit_offset_bitfields[NUM_BUCKETS][NUM_BITFIELD_INTS];
shared uint digit_sums[NUM_BUCKETS];
shared uint lookback_sums[NUM_BUCKETS];

#define SPIN_WHILE(value_to_write_to, value_to_read_from, condition) \
    do {\
        value_to_write_to = atomicCompSwap(value_to_read_from, 0, 0);\
    } while ((condition));

#define SPIN_WHILE_ZERO(value_to_write_to, value_to_read_from) \
    do {\
        value_to_write_to = atomicCompSwap(value_to_read_from, 0, 0);\
    } while (value_to_write_to == 0);

#define STATUS_VALUE_BITMASK 0x3FFFFFFF
#define STATUS_PARTIAL_SUM_BIT (1 << 30)
#define STATUS_GLOBAL_SUM_BIT (1 << 31)

uint lookback_for_global_sum(uint block_id, uint bucket_index) {
    memoryBarrier();
    barrier();
    // Decoupled lookback
    // Basically go back a block at a time, read the value,
    // if it's a partial sum, add it to the running global sum
    // if it's a globla sum, that represents the sum of all values to the left (including the current one), so we add and break
    // This will give us a bit faster of an answer rather than waiting for the block to the left to output it's global sum 
    // Roughly 3x faster than just waiting for previous block to update it's value
    uint global_sum = 0;
    uint previous_block_index = (block_id - 1);
    while (true) {
        uint control_value;
        SPIN_WHILE_ZERO(control_value, status_and_sum[previous_block_index * NUM_BUCKETS + bucket_index]);
        if ((control_value & STATUS_GLOBAL_SUM_BIT) != 0) {
            global_sum += control_value & STATUS_VALUE_BITMASK;
            break;
        }
        if ((control_value & STATUS_PARTIAL_SUM_BIT) != 0) {
            previous_block_index = max(previous_block_index - 1, 0); // NOTE: We rely on the first block always returning a global sum so this doesn't go on forever
            global_sum += control_value & STATUS_VALUE_BITMASK;
        }
    }

    return global_sum;
}

uint get_bitfield_index(uint n) {
    return n/32;
}

uint get_bitfield_bit(uint n) {
    uint bit = n & 31;
    return (1 << bit);
}


layout(local_size_x = THREAD_COUNT) in;
void main() {
    // One thread grabs the next block by incrementing the block counter
    if (gl_LocalInvocationID.x == 0) {
        // Written to shared memory so everyone can see which block they're in
        group_block_id = atomicAdd(block_counter, 1);
    }
    memoryBarrierShared();
    barrier();

    uint block_id = group_block_id;
    uint block_size = gl_WorkGroupSize.x;
    uint block_start_index = block_id * block_size;
    uint block_local_index = gl_LocalInvocationID.x;
    uint input_array_index = block_start_index + block_local_index;
    /*if (block_local_index < NUM_BITFIELD_INTS) {
        uint bitfield_index = block_local_index;
        // Zero bitfields for each digit
        for (int bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
            digit_offset_bitfields[bucket_index][bitfield_index] = 0;
            bitcounts[bucket_index][bitfield_index] = 0;
        }
    }*/

    // Zero bitfields for each digit
    if (block_local_index < NUM_BUCKETS) {
        uint bucket_index = block_local_index;
        for (uint bitfield_index = 0; bitfield_index < NUM_BITFIELD_INTS; bitfield_index++) {
            digit_offset_bitfields[bucket_index][bitfield_index] = 0;
        }
        digit_sums[bucket_index] = 0;
        lookback_sums[bucket_index] = 0;
    }

    memoryBarrierShared();
    barrier();

    // These values will be filled in if input_array_index < num_items, and only be used in a separate if input_array_index < num_items
    uint digit = 0;
    uint digit_start_index = 0;
    uint digit_offset = 0;
    uint input_key = 0;

    if (input_array_index < num_items) {
        input_key = source_keys[input_array_index];
        uint value = values[input_key];
        digit = (value >> (pass_number * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        digit_start_index = digit_start_indices[pass_number][digit];
        barrier();
        
        atomicOr(digit_offset_bitfields[digit][get_bitfield_index(block_local_index)], get_bitfield_bit(block_local_index));
    }

    memoryBarrierShared();
    barrier();


    if (input_array_index < num_items) {
        for (uint bucket_index = 0; bucket_index < NUM_BUCKETS; bucket_index++) {
            // Sum up the number of occurrences of this digit counting the bits in the bitfield to the left of the current position
            // First count up bits in each int group before this one (each int holds 32 bits which we can count up in a single bitCount call)
            uint int_to_stop_at = get_bitfield_index(block_local_index);
            uint sum_of_previous_bitfields = 0;
            for (uint bitfield_index = 0; bitfield_index < int_to_stop_at; bitfield_index++) {
                sum_of_previous_bitfields += bitCount(digit_offset_bitfields[bucket_index][bitfield_index]);
            }
            // Only count digits to the left of this one by masking out bits to the left
            uint bit = get_bitfield_bit(block_local_index);
            uint mask = bit == 0 ? 0 : bit - 1;
            sum_of_previous_bitfields += bitCount(digit_offset_bitfields[bucket_index][get_bitfield_index(block_local_index)] & mask);
            // Now we have the full count
            if (bucket_index == digit) {
                digit_offset = sum_of_previous_bitfields;
            }
        }
    }

    if (block_local_index < NUM_BUCKETS) {
        uint bucket_index = block_local_index;

        uint digit_sum = 0;
        for (uint bitfield_index = 0; bitfield_index < NUM_BITFIELD_INTS; bitfield_index++) { // TODO: Technically we could continue the sum above instead of doing a second loop, if we care
            digit_sum += bitCount(digit_offset_bitfields[bucket_index][bitfield_index]);
        }
        digit_sums[bucket_index] = digit_sum;
    }

    memoryBarrierShared();
    barrier();

    if (block_local_index < NUM_BUCKETS) {
        // Write out the partial sum for this block, for every bucket
        uint bucket_index = block_local_index;
        uint value_to_write = digit_sums[block_local_index]; // Last element of offsets holds the sum
        uint bit = block_id == 0 ? STATUS_GLOBAL_SUM_BIT : STATUS_PARTIAL_SUM_BIT; // First block is a global sum since no other blocks exsit to the left
        atomicExchange(status_and_sum[block_id * NUM_BUCKETS + bucket_index], bit | (value_to_write & STATUS_VALUE_BITMASK));
    }
    memoryBarrier();
    barrier();

    uint digit_local_offset = 0;
    if (block_id != 0) {
        if (block_local_index < NUM_BUCKETS) {
            uint bucket_index = block_local_index;
            uint lookback_sum = lookback_for_global_sum(block_id, bucket_index);

            // Write out the global sum for this block now that we know it
            uint value_to_write = digit_sums[block_local_index] + lookback_sum;
            atomicExchange(status_and_sum[block_id * NUM_BUCKETS + bucket_index], STATUS_GLOBAL_SUM_BIT | (value_to_write & STATUS_VALUE_BITMASK));

            // Write lookback result to shared memory so we can grab it later for when we want to know the sum for a single digit
            lookback_sums[bucket_index] = lookback_sum; // Reusing the shared memory to reduce the amount we have declared
        }
        memoryBarrier();
        barrier();
    }
    
    memoryBarrier();
    barrier();

    if (input_array_index < num_items) {
        uint digit_local_offset = 0;
        if (block_id != 0) {
            // Note digit_offset_bitfields[digit][0] is actually the sum of the number of occurrences of this digit to the left of this block. We're reusing the shared memory from before
            digit_local_offset = lookback_sums[digit];
        }

        barrier();

        uint output_index = digit_start_index + digit_offset + digit_local_offset; 
        destination_keys[output_index] = input_key;
    }
}

// digit_offset_bitfields is eventually going to tell us how much to offset this digit by to maintain the order
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