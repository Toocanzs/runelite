#include version_header
#include thread_config

uniform uint numItems;
uniform uint block;
uniform uint dim;

layout(std430, binding = 0) buffer _keys {
    uint keys[];
};

layout(std430, binding = 1) buffer _values {
    uint values[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    // NOTE: Requires a power of 2 sized array

    uint i = gl_GlobalInvocationID.x;
    uint j = i ^ block;
    if (j < i || i > numItems) return;

    uint key_i = keys[i];
    uint key_j = keys[j];

    uint value_i = values[key_i];
    uint value_j = values[key_j];

    if ((i&dim) == 0) {
        if (value_i > value_j) {
            keys[i] = key_j;
            keys[j] = key_i;
        }
    } else {
        if (value_i <= value_j) {
            keys[i] = key_j;
            keys[j] = key_i;
        }
    }
}

/*
The above is a direct translation of the following code:
https://github.com/nobnak/GPUMergeSortForUnity/blob/master/Assets/Packages/MergeSort/BitonicMergeSort.compute
I've changed the use of `int diff = (value_i - value_j) * ((i&dim) == 0 ? 1 : -1);` to instead be separate if statements, as the original code would overflow and produce incorrect results
License is included below.

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