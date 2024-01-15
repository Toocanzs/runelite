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
#include version_header
#include thread_config

layout(binding = 2) uniform isampler3D tileHeightSampler;

#include "comp_common.glsl"
#include "common.glsl"
#include "compute/priority.glsl"

layout(location = 0) uniform int modelCount;

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

layout(local_size_x = LOCAL_SIZE_X, local_size_y = LOCAL_SIZE_Y, local_size_z = LOCAL_SIZE_Z) in;
void main() {
    uint globalTriangleIndex = gl_GlobalInvocationID.x;
    int modelIndex = binary_search_for_model_index(modelCount, int(globalTriangleIndex));

    // Out of bounds invocations will get a -1 model index and return early
    if (modelIndex != -1) {
        modelinfo minfo = modelInfos[modelIndex];
        uint localTriangleIndex = globalTriangleIndex - minfo.modelSizePrefixSum;

        ivec4 vA;
        ivec4 vB;
        ivec4 vC;
        int _priority;
        int distance;
        get_face(localTriangleIndex, minfo, cameraYaw, cameraPitch, _priority, distance, vA, vB, vC);

        int adjustedPriority = map_face_priority(modelIndex, _priority, distance);

        int outOffset = minfo.idx;
        int toffset = minfo.toffset;
        int flags = minfo.flags;

        // we only have to order faces against others of the same priority
        const int priorityOffset = count_prio_offset(adjustedPriority, modelIndex);
        const int numOfPriority = modelPriorityData[modelIndex].totalMappedNum[adjustedPriority];
        const int start = priorityOffset;                // index of first face with this priority
        const int end = priorityOffset + numOfPriority;  // index of last face with this priority
        const int renderPriority = distance << 16 | int(~localTriangleIndex & 0xffffu);
        int myOffset = priorityOffset;

        // calculate position this face will be in
        for (int i = start; i < end; ++i) {
            if (renderPriority < renderPriorities[minfo.modelSizePrefixSum + i].distanceBasedRenderPriority) {
            ++myOffset;
            }
        }

        // position into scene
        ivec4 pos = ivec4(minfo.x, minfo.y, minfo.z, 0);
        vA += pos;
        vB += pos;
        vC += pos;

        // apply hillskew
        int plane = (flags >> 24) & 3;
        int hillskew = (flags >> 26) & 1;
        vA = hillskew_vertex(vA, hillskew, minfo.y, plane);
        vB = hillskew_vertex(vB, hillskew, minfo.y, plane);
        vC = hillskew_vertex(vC, hillskew, minfo.y, plane);

        // write to out buffer
        vertexOutBuffer[outOffset + myOffset * 3] = vA;
        vertexOutBuffer[outOffset + myOffset * 3 + 1] = vB;
        vertexOutBuffer[outOffset + myOffset * 3 + 2] = vC;

        if (toffset < 0) {
            uvOutBuffer[outOffset + myOffset * 3] = vec4(0);
            uvOutBuffer[outOffset + myOffset * 3 + 1] = vec4(0);
            uvOutBuffer[outOffset + myOffset * 3 + 2] = vec4(0);
        } else {
            vec4 texA, texB, texC;

            if (flags >= 0) {
            texA = tempTextureBuffer[toffset + localTriangleIndex * 3];
            texB = tempTextureBuffer[toffset + localTriangleIndex * 3 + 1];
            texC = tempTextureBuffer[toffset + localTriangleIndex * 3 + 2];
            } else {
            texA = textureBuffer[toffset + localTriangleIndex * 3];
            texB = textureBuffer[toffset + localTriangleIndex * 3 + 1];
            texC = textureBuffer[toffset + localTriangleIndex * 3 + 2];
            }

            int orientation = flags & 0x7ff;
            uvOutBuffer[outOffset + myOffset * 3] = vec4(texA.x, rotatef(texA.yzw, orientation) + pos.xyz);
            uvOutBuffer[outOffset + myOffset * 3 + 1] = vec4(texB.x, rotatef(texB.yzw, orientation) + pos.xyz);
            uvOutBuffer[outOffset + myOffset * 3 + 2] = vec4(texC.x, rotatef(texC.yzw, orientation) + pos.xyz);
        }
    }
}