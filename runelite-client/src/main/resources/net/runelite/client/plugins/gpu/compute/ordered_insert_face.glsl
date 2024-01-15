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

#include "comp_common.glsl"
#include "common.glsl"
#include "compute/priority.glsl"

layout(location = 0) uniform int modelCount;

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
        int priority;
        int distance;
        get_face(localTriangleIndex, minfo, cameraYaw, cameraPitch, priority, distance, vA, vB, vC);

        int adjustedPriority = map_face_priority(modelIndex, priority, distance);
        int priorityIndex = renderPriorities[globalTriangleIndex].priorityIndex;

        // calculate base offset into renderPris based on number of faces with a lower priority
        int baseOff = count_prio_offset(adjustedPriority, modelIndex);
        // the furthest faces draw first, and have the highest priority.
        // if two faces have the same distance, the one with the
        // lower id draws first.
        renderPriorities[minfo.modelSizePrefixSum + baseOff + priorityIndex].distanceBasedRenderPriority = distance << 16 | int(~localTriangleIndex & 0xffffu);
    }
}