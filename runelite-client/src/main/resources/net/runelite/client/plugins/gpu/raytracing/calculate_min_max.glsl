#include version_header
#include thread_config

uniform uint num_items;

layout(std430, binding = 0) readonly buffer _vertex_buffer {
    ivec4 vertex_buffer[];
};

struct MinMax {
    int minX;
    int minY;
    int minZ;

    int maxX;
    int maxY;
    int maxZ;
};

layout(std430, binding = 1) buffer _min_max {
    MinMax global_min_max;
};

shared MinMax local_min_max;

layout(local_size_x = THREAD_COUNT) in;
void main() {
    // Setup shared min/max to int max/min values
    if (gl_LocalInvocationID.x == 0) {
        local_min_max.minX = 2147483647;
        local_min_max.minX = 2147483647;
        local_min_max.minX = 2147483647;

        local_min_max.maxX = -2147483648;
        local_min_max.maxY = -2147483648;
        local_min_max.maxZ = -2147483648;
    }

    groupMemoryBarrier();
    barrier();

    // Gather min/max in shared memory, then min/max to global
    // This reduces the amount of global atomic operations we do (goes from numItems global atomic operations to just numBlocks)
    if (gl_GlobalInvocationID.x < num_items) {
        ivec4 vertex = vertex_buffer[gl_GlobalInvocationID.x];
        atomicMin(local_min_max.minX, vertex.x);
        atomicMin(local_min_max.minY, vertex.y);
        atomicMin(local_min_max.minZ, vertex.z);

        atomicMax(local_min_max.maxX, vertex.x);
        atomicMax(local_min_max.maxY, vertex.y);
        atomicMax(local_min_max.maxZ, vertex.z);
    }

    groupMemoryBarrier();
    barrier();

    // One thread does the global atomic min/max
    if (gl_LocalInvocationID.x == 0) {
        atomicMin(global_min_max.minX, local_min_max.minX);
        atomicMin(global_min_max.minY, local_min_max.minY);
        atomicMin(global_min_max.minZ, local_min_max.minZ);

        atomicMax(global_min_max.maxX, local_min_max.maxX);
        atomicMax(global_min_max.maxY, local_min_max.maxY);
        atomicMax(global_min_max.maxZ, local_min_max.maxZ);
    }
}