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

layout(binding = 2) uniform isampler3D tileHeightSampler;

// Calculate adjusted priority for a face with a given priority, distance, and
// model global min10 and face distance averages. This allows positioning faces
// with priorities 10/11 into the correct 'slots' resulting in 18 possible
// adjusted priorities
int priority_map(int p, int distance, int _min10, int avg1, int avg2, int avg3) {
  // (10, 11)  0  1  2  (10, 11)  3  4  (10, 11)  5  6  7  8  9  (10, 11)
  //   0   1   2  3  4    5   6   7  8    9  10  11 12 13 14 15   16  17
  switch (p) {
    case 0:
      return 2;
    case 1:
      return 3;
    case 2:
      return 4;
    case 3:
      return 7;
    case 4:
      return 8;
    case 5:
      return 11;
    case 6:
      return 12;
    case 7:
      return 13;
    case 8:
      return 14;
    case 9:
      return 15;
    case 10:
      if (distance > avg1) {
        return 0;
      } else if (distance > avg2) {
        return 5;
      } else if (distance > avg3) {
        return 9;
      } else {
        return 16;
      }
    case 11:
      if (distance > avg1 && _min10 > avg1) {
        return 1;
      } else if (distance > avg2 && (_min10 > avg1 || _min10 > avg2)) {
        return 6;
      } else if (distance > avg3 && (_min10 > avg1 || _min10 > avg2 || _min10 > avg3)) {
        return 10;
      } else {
        return 17;
      }
    default:
      // this can't happen unless an invalid priority is sent. just assume 0.
      return 0;
  }
}

void get_face(uint localId, modelinfo minfo, float cameraYaw, float cameraPitch, out int prio, out int dis, out ivec4 o1, out ivec4 o2, out ivec4 o3) {
  int size = minfo.size;
  int offset = minfo.offset;
  int flags = minfo.flags;
  uint ssboOffset;

  if (localId < size) {
    ssboOffset = localId;
  } else {
    ssboOffset = 0;
  }

  ivec4 thisA;
  ivec4 thisB;
  ivec4 thisC;

  // Grab triangle vertices from the correct buffer
  if (flags < 0) {
    thisA = vb[offset + ssboOffset * 3];
    thisB = vb[offset + ssboOffset * 3 + 1];
    thisC = vb[offset + ssboOffset * 3 + 2];
  } else {
    thisA = tempvb[offset + ssboOffset * 3];
    thisB = tempvb[offset + ssboOffset * 3 + 1];
    thisC = tempvb[offset + ssboOffset * 3 + 2];
  }

  if (localId < size) {
    int orientation = flags & 0x7ff;

    // rotate for model orientation
    ivec4 thisrvA = rotate(thisA, orientation);
    ivec4 thisrvB = rotate(thisB, orientation);
    ivec4 thisrvC = rotate(thisC, orientation);

    // calculate distance to face
    int thisPriority = (thisA.w >> 16) & 0xff;  // all vertices on the face have the same priority
    int thisDistance = face_distance(thisrvA, thisrvB, thisrvC, cameraYaw, cameraPitch);

    o1 = thisrvA;
    o2 = thisrvB;
    o3 = thisrvC;

    prio = thisPriority;
    dis = thisDistance;
  } else {
    o1 = ivec4(0);
    o2 = ivec4(0);
    o3 = ivec4(0);
    prio = 0;
    dis = 0;
  }
}

void add_face_prio_distance(uint localId, modelinfo minfo, ivec4 thisrvA, ivec4 thisrvB, ivec4 thisrvC, int thisPriority, int thisDistance, ivec4 pos) {
  if (localId < minfo.size) {
    // if the face is not culled, it is calculated into priority distance averages
    if (face_visible(thisrvA, thisrvB, thisrvC, pos)) {
      atomicAdd(totalNum[thisPriority], 1);
      atomicAdd(totalDistance[thisPriority], thisDistance);

      // calculate minimum distance to any face of priority 10 for positioning the 11 faces later
      if (thisPriority == 10) {
        atomicMin(min10, thisDistance);
      }
    }
  }
}

int map_face_priority(uint localId, modelinfo minfo, int thisPriority, int thisDistance) {
  int size = minfo.size;

  // Compute average distances for 0/2, 3/4, and 6/8

  if (localId < size) {
    int avg1 = 0;
    int avg2 = 0;
    int avg3 = 0;

    if (totalNum[1] > 0 || totalNum[2] > 0) {
      avg1 = (totalDistance[1] + totalDistance[2]) / (totalNum[1] + totalNum[2]);
    }

    if (totalNum[3] > 0 || totalNum[4] > 0) {
      avg2 = (totalDistance[3] + totalDistance[4]) / (totalNum[3] + totalNum[4]);
    }

    if (totalNum[6] > 0 || totalNum[8] > 0) {
      avg3 = (totalDistance[6] + totalDistance[8]) / (totalNum[6] + totalNum[8]);
    }

    int adjPrio = priority_map(thisPriority, thisDistance, min10, avg1, avg2, avg3);

    return adjPrio;
  }

  return 0;
}

uint render_priority(int adjPrio, int distance, uint localId) {
  #define PRIORITY_BITS 5  // 18 priorities
  #define DISTANCE_BITS 14 // arbitrary amount of distance bits. Needs to at least fit -2048 to 2048 ints converted to uints, so at least 4096
  #define LOCALID_BITS 13  // 6144 maximum triangles

  #define PRIOIRTY_MASK ((1 << PRIORITY_BITS) - 1)

  #define DISTANCE_MASK ((1 << DISTANCE_BITS) - 1)
  #define DISTANCE_ADD (1 << (DISTANCE_BITS - 1)) // Adding the minimum signed integer value to convert to uint

  #define LOCALID_MASK ((1 << LOCALID_BITS) - 1)

  uint p = uint(adjPrio) & PRIOIRTY_MASK;
  uint d = uint(-distance + DISTANCE_ADD) & DISTANCE_MASK;
  uint l = localId & LOCALID_MASK;
  return (p << (DISTANCE_BITS + LOCALID_BITS)) | (d << DISTANCE_BITS) | l;
}

void insert_face(uint localId, modelinfo minfo, int adjPrio, int distance) {
  int size = minfo.size;

  if (localId < size) {
    // the furthest faces draw first, and have the highest priority.
    // if two faces have the same distance, the one with the
    // lower id draws first.
    // the sorted order of these dictate the order in which to draw the triangles
    renderPris[localId] = render_priority(adjPrio, distance, localId);
  }
}

int tile_height(int z, int x, int y) {
#define ESCENE_OFFSET 40  // (184-104)/2
  return texelFetch(tileHeightSampler, ivec3(x + ESCENE_OFFSET, y + ESCENE_OFFSET, z), 0).r << 3;
}

ivec4 hillskew_vertex(ivec4 v, int hillskew, int y, int plane) {
  if (hillskew == 1) {
    int px = v.x & 127;
    int pz = v.z & 127;
    int sx = v.x >> 7;
    int sz = v.z >> 7;
    int h1 = px * tile_height(plane, sx + 1, sz) + (128 - px) * tile_height(plane, sx, sz) >> 7;
    int h2 = px * tile_height(plane, sx + 1, sz + 1) + (128 - px) * tile_height(plane, sx, sz + 1) >> 7;
    int h3 = pz * h2 + (128 - pz) * h1 >> 7;
    return ivec4(v.x, v.y + h3 - y, v.z, v.w);
  } else {
    return v;
  }
}

void sort_and_insert(uint localId, modelinfo minfo, int thisPriority, int thisDistance, ivec4 thisrvA, ivec4 thisrvB, ivec4 thisrvC) {
  int size = minfo.size;

  if (localId < size) {
    int outOffset = minfo.idx;
    int toffset = minfo.toffset;
    int flags = minfo.flags;
    const uint renderPriority = render_priority(thisPriority, thisDistance, localId);

    int low = 0;
    int high = size - 1;
    int resultIndex = -1;
    while (low <= high) {
      int mid = low + (high - low) / 2;
      if (renderPris[mid] == renderPriority) {
        resultIndex = mid;
        break;
      } else if (renderPris[mid] < renderPriority) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    bool found = low <= high;
    if (found) {
      int myOffset = resultIndex;

      // position into scene
      ivec4 pos = ivec4(minfo.x, minfo.y, minfo.z, 0);
      thisrvA += pos;
      thisrvB += pos;
      thisrvC += pos;

      // apply hillskew
      int plane = (flags >> 24) & 3;
      int hillskew = (flags >> 26) & 1;
      thisrvA = hillskew_vertex(thisrvA, hillskew, minfo.y, plane);
      thisrvB = hillskew_vertex(thisrvB, hillskew, minfo.y, plane);
      thisrvC = hillskew_vertex(thisrvC, hillskew, minfo.y, plane);

      // write to out buffer
      vout[outOffset + myOffset * 3] = thisrvA;
      vout[outOffset + myOffset * 3 + 1] = thisrvB;
      vout[outOffset + myOffset * 3 + 2] = thisrvC;

      if (toffset < 0) {
        uvout[outOffset + myOffset * 3] = vec4(0);
        uvout[outOffset + myOffset * 3 + 1] = vec4(0);
        uvout[outOffset + myOffset * 3 + 2] = vec4(0);
      } else {
        vec4 texA, texB, texC;

        if (flags >= 0) {
          texA = temptexb[toffset + localId * 3];
          texB = temptexb[toffset + localId * 3 + 1];
          texC = temptexb[toffset + localId * 3 + 2];
        } else {
          texA = texb[toffset + localId * 3];
          texB = texb[toffset + localId * 3 + 1];
          texC = texb[toffset + localId * 3 + 2];
        }

        int orientation = flags & 0x7ff;
        uvout[outOffset + myOffset * 3] = vec4(texA.x, rotatef(texA.yzw, orientation) + pos.xyz);
        uvout[outOffset + myOffset * 3 + 1] = vec4(texB.x, rotatef(texB.yzw, orientation) + pos.xyz);
        uvout[outOffset + myOffset * 3 + 2] = vec4(texC.x, rotatef(texC.yzw, orientation) + pos.xyz);
      }
    }
  }
}
