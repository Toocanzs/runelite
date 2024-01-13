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

uniform int unorderedModelCount;

layout(local_size_x = LOCAL_SIZE_X, local_size_y = LOCAL_SIZE_Y, local_size_z = LOCAL_SIZE_Z) in;

int binary_search_for_model_index(int modelCount, int triangleIndex) {
  int low = 0;
  int high = modelCount - 1;
  while (low <= high) {
    int mid = low + (high - low) / 2;

    modelinfo info = modelInfos[mid];
    int triangleStartIndex = info.modelCountPrefixSum;
    int triangleEndIndex = info.modelCountPrefixSum + info.size;

    if (triangleIndex >= triangleStartIndex && triangleIndex < triangleEndIndex) {
      return mid;
    }
    else if (triangleIndex >= triangleEndIndex) {
      low = mid + 1;
    }
    else {
      high = mid - 1;
    }
  }
  return -1;
}

void main() {
  uint globalTriangleIndex = gl_GlobalInvocationID.x;
  int modelIndex = binary_search_for_model_index(unorderedModelCount, int(globalTriangleIndex));
  // Out of bounds invocations will get a -1 model index and return early
  if (modelIndex != -1) {
    modelinfo minfo = modelInfos[modelIndex];

    int offset = minfo.offset;
    int size = minfo.size;
    int outOffset = minfo.idx;
    int toffset = minfo.toffset;
    int flags = minfo.flags;
    uint modelTriangleIndex = globalTriangleIndex - minfo.modelCountPrefixSum;

    uint ssboOffset = modelTriangleIndex;
    ivec4 thisA, thisB, thisC;

    // Grab triangle vertices from the correct buffer
    if (flags < 0) {
      thisA = vertexBuffer[offset + ssboOffset * 3];
      thisB = vertexBuffer[offset + ssboOffset * 3 + 1];
      thisC = vertexBuffer[offset + ssboOffset * 3 + 2];
    } else {
      thisA = tempVertexBuffer[offset + ssboOffset * 3];
      thisB = tempVertexBuffer[offset + ssboOffset * 3 + 1];
      thisC = tempVertexBuffer[offset + ssboOffset * 3 + 2];
    }

    uint myOffset = modelTriangleIndex;
    ivec4 pos = ivec4(minfo.x, minfo.y, minfo.z, 0);
    ivec4 texPos = pos.wxyz;

    // position vertices in scene and write to out buffer
    vertexOutBuffer[outOffset + myOffset * 3] = pos + thisA;
    vertexOutBuffer[outOffset + myOffset * 3 + 1] = pos + thisB;
    vertexOutBuffer[outOffset + myOffset * 3 + 2] = pos + thisC;

    if (toffset < 0) {
      uvOutBuffer[outOffset + myOffset * 3] = vec4(0);
      uvOutBuffer[outOffset + myOffset * 3 + 1] = vec4(0);
      uvOutBuffer[outOffset + myOffset * 3 + 2] = vec4(0);
    } else if (flags >= 0) {
      uvOutBuffer[outOffset + myOffset * 3] = texPos + tempTextureBuffer[toffset + modelTriangleIndex * 3];
      uvOutBuffer[outOffset + myOffset * 3 + 1] = texPos + tempTextureBuffer[toffset + modelTriangleIndex * 3 + 1];
      uvOutBuffer[outOffset + myOffset * 3 + 2] = texPos + tempTextureBuffer[toffset + modelTriangleIndex * 3 + 2];
    } else {
      uvOutBuffer[outOffset + myOffset * 3] = texPos + textureBuffer[toffset + modelTriangleIndex * 3];
      uvOutBuffer[outOffset + myOffset * 3 + 1] = texPos + textureBuffer[toffset + modelTriangleIndex * 3 + 1];
      uvOutBuffer[outOffset + myOffset * 3 + 2] = texPos + textureBuffer[toffset + modelTriangleIndex * 3 + 2];
    }
  }
}
