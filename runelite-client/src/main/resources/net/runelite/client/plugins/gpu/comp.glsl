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

#include "comp_common.glsl"
uniform int orderedModelCount;

layout(local_size_x = LOCAL_SIZE_X, local_size_y = LOCAL_SIZE_Y, local_size_z = LOCAL_SIZE_Z) in;

#include "common.glsl"
#include "priority_render.glsl"

void main() {
  uint globalTriangleIndex = gl_GlobalInvocationID.x;
  // Out of bounds invocations will get a -1 model index and return early
  int modelIndex = binary_search_for_model_index(orderedModelCount, int(globalTriangleIndex));
  modelinfo minfo;
  ivec4 pos;
  uint localId;

  ivec4 vA;
  ivec4 vB;
  ivec4 vC;
  int prio;
  int dis;
  
  if (modelIndex != -1) {
    minfo = modelInfos[modelIndex];
    localId = globalTriangleIndex - minfo.modelSizePrefixSum;
    pos = ivec4(minfo.x, minfo.y, minfo.z, 0);

    if (localId == 0) {
      priorityData[modelIndex].min10 = 6000;
      for (int i = 0; i < 12; ++i) {
        priorityData[modelIndex].totalNum[i] = 0;
        priorityData[modelIndex].totalDistance[i] = 0;
      }
      for (int i = 0; i < 18; ++i) {
        priorityData[modelIndex].totalMappedNum[i] = 0;
      }
    }

    get_face(localId, minfo, cameraYaw, cameraPitch, prio, dis, vA, vB, vC);
  }

  groupMemoryBarrier();
  barrier();

  if (modelIndex != -1) {
    add_face_prio_distance(localId, modelIndex, minfo, vA, vB, vC, prio, dis, pos);
  }

  groupMemoryBarrier();
  barrier();

  int prioAdj;
  int idx;
  if (modelIndex != -1) {
    idx = map_face_priority(localId, modelIndex, minfo, prio, dis, prioAdj);
  }

  groupMemoryBarrier();
  barrier();
  if (modelIndex != -1) {
    insert_face(localId, modelIndex, minfo, prioAdj, dis, idx);
  }

  groupMemoryBarrier();
  barrier();
  if (modelIndex != -1) {
    sort_and_insert(localId, modelIndex, minfo, prioAdj, dis, vA, vB, vC);
  }
}
