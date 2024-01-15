/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * Copyright (c) 2024, Toocanzs <https://github.com/toocanzs>
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

void get_face(uint localTriangleIndex, modelinfo minfo, float cameraYaw, float cameraPitch, out int prio, out int dis, out ivec4 o1, out ivec4 o2, out ivec4 o3) {
  int size = minfo.size;
  int offset = minfo.offset;
  int flags = minfo.flags;

  ivec4 thisA;
  ivec4 thisB;
  ivec4 thisC;

  // Grab triangle vertices from the correct buffer
  if (flags < 0) {
    thisA = vertexBuffer[offset + localTriangleIndex * 3];
    thisB = vertexBuffer[offset + localTriangleIndex * 3 + 1];
    thisC = vertexBuffer[offset + localTriangleIndex * 3 + 2];
  } else {
    thisA = tempVertexBuffer[offset + localTriangleIndex * 3];
    thisB = tempVertexBuffer[offset + localTriangleIndex * 3 + 1];
    thisC = tempVertexBuffer[offset + localTriangleIndex * 3 + 2];
  }

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
}

// calculate the number of faces with a lower adjusted priority than
// the given adjusted priority
int count_prio_offset(int priority, uint modelIndex) {
  // this shouldn't ever be outside of (0, 17) because it is the return value from priority_map
  priority = clamp(priority, 0, 17);
  int total = 0;
  for (int i = 0; i < priority; i++) {
    total += modelPriorityData[modelIndex].totalMappedNum[i];
  }
  return total;
}

int map_face_priority(uint modelIndex, int thisPriority, int thisDistance) {
  // Compute average distances for 0/2, 3/4, and 6/8

  int avg1 = 0;
  int avg2 = 0;
  int avg3 = 0;

  if (modelPriorityData[modelIndex].totalNum[1] > 0 || modelPriorityData[modelIndex].totalNum[2] > 0) {
    avg1 = (modelPriorityData[modelIndex].totalDistance[1] + modelPriorityData[modelIndex].totalDistance[2]) / (modelPriorityData[modelIndex].totalNum[1] + modelPriorityData[modelIndex].totalNum[2]);
  }

  if (modelPriorityData[modelIndex].totalNum[3] > 0 || modelPriorityData[modelIndex].totalNum[4] > 0) {
    avg2 = (modelPriorityData[modelIndex].totalDistance[3] + modelPriorityData[modelIndex].totalDistance[4]) / (modelPriorityData[modelIndex].totalNum[3] + modelPriorityData[modelIndex].totalNum[4]);
  }

  if (modelPriorityData[modelIndex].totalNum[6] > 0 || modelPriorityData[modelIndex].totalNum[8] > 0) {
    avg3 = (modelPriorityData[modelIndex].totalDistance[6] + modelPriorityData[modelIndex].totalDistance[8]) / (modelPriorityData[modelIndex].totalNum[6] + modelPriorityData[modelIndex].totalNum[8]);
  }

  int adjustedPriority = priority_map(thisPriority, thisDistance, modelPriorityData[modelIndex].min10, avg1, avg2, avg3);
  return adjustedPriority;
}