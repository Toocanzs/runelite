#include version_header
#include thread_config

uniform uint unpaddedItemCount;
uniform uint paddedArraySize;

layout(std430, binding = 0) writeonly buffer _keys {
    uint keys[];
};

layout(std430, binding = 1) writeonly buffer _values {
    uint values[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < paddedArraySize) {
        if (gl_GlobalInvocationID.x >= unpaddedItemCount) {
            values[gl_GlobalInvocationID.x] = 0xFFFFFFFF; // Pad with max value so when sorted these end up at the end of the array
        }
        keys[gl_GlobalInvocationID.x] = gl_GlobalInvocationID.x;
    }
}

/*
The above is a direct translation of the following code:
https://github.com/nobnak/GPUMergeSortForUnity/blob/master/Assets/Packages/MergeSort/BitonicMergeSort.compute

MIT License

Copyright (c) 2019 Nakata Nobuyuki (仲田将之)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/