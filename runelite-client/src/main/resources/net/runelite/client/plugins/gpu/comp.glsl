/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include version_header

#include thread_config

shared int totalNum[12];       // number of faces with a given priority
shared int totalDistance[12];  // sum of distances to faces of a given priority
shared int min10;                                        // minimum distance to a face of priority 10
shared uint renderPris[THREAD_COUNT * FACES_PER_THREAD];  // priority for face draw order

#define BITS_PER_PASS 4
#define RADIX_PASS_COUNT ((32 + BITS_PER_PASS - 1) / BITS_PER_PASS)
#define NUM_BUCKETS (1 << BITS_PER_PASS)
#define NUM_BITFIELDS ((THREAD_COUNT*FACES_PER_THREAD)/32)

shared uint radixDigitCounts[NUM_BUCKETS];
shared uint radixBitmasks[NUM_BUCKETS][NUM_BITFIELDS];

#include "comp_common.glsl"

layout(local_size_x = THREAD_COUNT) in;

#include "common.glsl"
#include "priority_render.glsl"

uint get_bitfield_index(uint n) {
    return n/32;
}

uint get_bitfield_bit(uint n) {
    uint bit = n & 31;
    return (1 << bit);
}

void main() {
  uint groupId = gl_WorkGroupID.x;
  uint localId = gl_LocalInvocationID.x * FACES_PER_THREAD;
  modelinfo minfo = ol[groupId];
  ivec4 pos = ivec4(minfo.x, minfo.y, minfo.z, 0);

  if (gl_LocalInvocationID.x < 12) {
    totalNum[gl_LocalInvocationID.x] = 0;
    totalDistance[gl_LocalInvocationID.x] = 0;
  }
  if (gl_LocalInvocationID.x == 0) {
    min10 = 6000;
  }

  memoryBarrierShared();
  barrier();

  int prio[FACES_PER_THREAD];
  int dis[FACES_PER_THREAD];
  ivec4 vA[FACES_PER_THREAD];
  ivec4 vB[FACES_PER_THREAD];
  ivec4 vC[FACES_PER_THREAD];

  for (int i = 0; i < FACES_PER_THREAD; i++) {
    get_face(localId + i, minfo, cameraYaw, cameraPitch, prio[i], dis[i], vA[i], vB[i], vC[i]);
  }

  memoryBarrierShared();
  barrier();

  for (int i = 0; i < FACES_PER_THREAD; i++) {
    add_face_prio_distance(localId + i, minfo, vA[i], vB[i], vC[i], prio[i], dis[i], pos);
  }

  memoryBarrierShared();
  barrier();

  int prioAdj[FACES_PER_THREAD];
  for (int i = 0; i < FACES_PER_THREAD; i++) {
    prioAdj[i] = map_face_priority(localId + i, minfo, prio[i], dis[i]);
    insert_face(localId + i, minfo, prioAdj[i], dis[i]);
  }

  memoryBarrierShared();
  barrier();

  const uint MAX_BITFIELD = min(NUM_BITFIELDS, get_bitfield_index(minfo.size)+1);
  
  for (uint passNumber = 0; passNumber < RADIX_PASS_COUNT; passNumber++) {
    if (gl_LocalInvocationID.x < NUM_BUCKETS) {
      radixDigitCounts[gl_LocalInvocationID.x] = 0;
    }
    #define ITERATIONS ((NUM_BITFIELDS*NUM_BUCKETS + THREAD_COUNT - 1) / THREAD_COUNT)
    for (int i = 0; i < ITERATIONS; i++) {
      uint baseIndex = gl_LocalInvocationID.x * ITERATIONS;
      uint index = baseIndex + i;
      uint bucketIndex = index % NUM_BUCKETS;
      uint bitfieldIndex = index / NUM_BUCKETS;
      if (bitfieldIndex < MAX_BITFIELD) {
        radixBitmasks[bucketIndex][bitfieldIndex] = 0;
      }
    }

    // We read the values now so we can do a read->barrier->write later, which gets rid of the need for a second temporary array
    uint value[FACES_PER_THREAD];
    for (uint i = 0; i < FACES_PER_THREAD; i++) {
      if ((localId + i) < minfo.size) {
        value[i] = renderPris[localId + i];
      }
    }

    memoryBarrierShared();
    barrier();

    for (uint i = 0; i < FACES_PER_THREAD; i++) {
      if ((localId + i) < minfo.size) {
        uint digit = (value[i] >> (passNumber * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        atomicAdd(radixDigitCounts[digit], 1);
        uint bitfieldIndex = get_bitfield_index(localId + i);
        uint bit = get_bitfield_bit(localId + i);
        atomicOr(radixBitmasks[digit][bitfieldIndex], bit);
      }
    }

    memoryBarrierShared();
    barrier();

    // Read the masked bit counts for the last bitfield because we'll need it later and we're about to overwrite the bitfields with a prefix sum of bitcounts
    uint maskedBitcounts[FACES_PER_THREAD];
    for (uint i = 0; i < FACES_PER_THREAD; i++) {
      uint digit = (value[i] >> (passNumber * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
      uint endBitfield = get_bitfield_index(localId + i);
      // Only count digits to the left of this one by masking out bits to the left
      uint bit = get_bitfield_bit(localId + i);
      uint mask = bit == 0 ? 0 : bit - 1;
      maskedBitcounts[i] = bitCount(radixBitmasks[digit][endBitfield] & mask);
    }

    memoryBarrierShared();
    barrier();
    
    // Inclusive prefix sum of digit counts gives us the digit start index
    if (gl_LocalInvocationID.x == 0) {
      uint sum = 0;
      for (int i = 0; i < NUM_BUCKETS; i++) {
        sum += radixDigitCounts[i];
        radixDigitCounts[i] = sum;
      }
    }

    // Exclusive prefix sum of bitcounts for the bitfields for each digit gives us the number of same digits that appear before a given digit
    if (gl_LocalInvocationID.x < NUM_BUCKETS) {
      uint bucketIndex = gl_LocalInvocationID.x;
      uint sum = 0;
      for (uint bitfieldIndex = 0; bitfieldIndex < MAX_BITFIELD; bitfieldIndex++) {
        uint temp = bitCount(radixBitmasks[bucketIndex][bitfieldIndex]);
        radixBitmasks[bucketIndex][bitfieldIndex] = sum;
        sum += temp;
      }
    }
    
    memoryBarrierShared();
    barrier();

    for (uint i = 0; i < FACES_PER_THREAD; i++) {
      if ((localId + i) < minfo.size) {
        uint digit = (value[i] >> (passNumber * BITS_PER_PASS)) & (NUM_BUCKETS - 1);
        uint endBitfield = get_bitfield_index(localId + i);
        // digitRelativeIndex is the index of the digit relative to other values with the same digit
        // For example with [1,2,2,2,3], there are three 2s, and if we convert the digits to letters we get
        // [A, B, B, B, C]
        // Now to differentiate the same letters, we give them a number in the order they appear
        // [A0, B0, B1, B2, C0]
        // digitRelativeIndex is the number given to each letter in the example
        // So for the third 2 digit to appear in the array, digitRelativeIndex = 2
        // It's obtained by doing a prefix sum on a bitmask for each digit
        // the bitmask for digit 2 in the example is [0,1,1,1,0]
        uint digitRelativeIndex = radixBitmasks[digit][endBitfield] + maskedBitcounts[i]; 
        uint digitStartIndex = digit == 0 ? 0 : radixDigitCounts[digit-1]; // -1 because we did an inclusive prefix sum
        uint outputIndex = digitStartIndex + digitRelativeIndex;
        renderPris[outputIndex] = value[i];
      }
    }

    memoryBarrierShared();
    barrier();
  }
  
  for (int i = 0; i < FACES_PER_THREAD; i++) {
    sort_and_insert(localId + i, minfo, prioAdj[i], dis[i], vA[i], vB[i], vC[i]);
  }
}