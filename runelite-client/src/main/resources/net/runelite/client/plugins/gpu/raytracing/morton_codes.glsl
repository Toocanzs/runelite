#include version_header
#include thread_config

uniform uint num_items;

struct KeyValue {
    uint key;
    uint value;
};

struct MinMax {
    int minX;
    int minY;
    int minZ;

    int maxX;
    int maxY;
    int maxZ;
};

layout(std430, binding = 0) readonly buffer _vertex_buffer {
    ivec4 vertex_buffer[];
};

layout(std430, binding = 1) readonly buffer _min_max {
    MinMax global_min_max;
};

layout(std430, binding = 2) writeonly buffer _key_values {
    KeyValue key_values[];
};

uint expand_bits(uint v) {
    // https://developer.nvidia.com/blog/thinking-parallel-part-iii-tree-construction-gpu/
    v = (v * 0x00010001u) & 0xFF0000FFu;
    v = (v * 0x00000101u) & 0x0F00F00Fu;
    v = (v * 0x00000011u) & 0xC30C30C3u;
    v = (v * 0x00000005u) & 0x49249249u;
    return v;
}


uint get_morton_code(vec3 aabb_center) {
    // https://developer.nvidia.com/blog/thinking-parallel-part-iii-tree-construction-gpu/
    vec3 _min = vec3(global_min_max.minX, global_min_max.minY, global_min_max.minZ);
    vec3 _max = vec3(global_min_max.maxX, global_min_max.maxY, global_min_max.maxZ);

    // Convert to float 0 to 1 based on the min/max
    vec3 v01 = (aabb_center - _min) / (_max - _min);

    v01.x = min(max(v01.x * 1024.0f, 0.0f), 1023.0f);
    v01.y = min(max(v01.y * 1024.0f, 0.0f), 1023.0f);
    v01.z = min(max(v01.z * 1024.0f, 0.0f), 1023.0f);

    uint xx = expand_bits(uint(v01.x));
    uint yy = expand_bits(uint(v01.y));
    uint zz = expand_bits(uint(v01.z));

    return xx * 4 + yy * 2 + zz;
}

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_items) {
        uint triangle_index = gl_GlobalInvocationID.x;
        uint base_vertex_index = triangle_index * 3;

        ivec3 vA = vertex_buffer[base_vertex_index + 0].xyz;
        ivec3 vB = vertex_buffer[base_vertex_index + 1].xyz;
        ivec3 vC = vertex_buffer[base_vertex_index + 2].xyz;

        ivec3 aabb_min = min(vA, min(vB, vC));
        ivec3 aabb_max = max(vA, max(vB, vC));

        vec3 aabb_center = vec3(aabb_min + aabb_max) / 2.0;

        uint morton_code = get_morton_code(aabb_center);
        key_values[triangle_index] = KeyValue(triangle_index, morton_code);
    }
}