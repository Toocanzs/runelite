#include version_header
#include thread_config

uniform uint num_bvh_nodes;
uniform uint leaf_node_offset;

struct KeyValue {
    uint key;
    uint value;
};

struct BVHNode {
    // NOTE: The placement of the vec3 components is important here.
    // We want no padding to reduce the total size of this struct, and since it would pad up to vec4 size, we put a uint after the vec3 in place of the would-be padding
    vec3 aabb_min;
    uint parent_index;

    vec3 aabb_max;
    uint left_child_index;

    uint right_child_index;
    uint leaf_object_id_plus_one; // if this node is a leaf this will be != 0
    uint thread_counter;
    uint _unused; // To pad up to 12*4 bytes (may not be needed?)
};

layout(std430, binding = 0) writeonly buffer _nodes {
    BVHNode nodes[];
};

layout(std430, binding = 1) readonly buffer _sorted_key_values {
    KeyValue sorted_key_values[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_bvh_nodes) {
        uint node_index = gl_GlobalInvocationID.x;

        nodes[node_index].thread_counter = 0;
        if (node_index >= leaf_node_offset) {
            nodes[node_index].leaf_object_id_plus_one = sorted_key_values[node_index - leaf_node_offset].key + 1;
        } else {
            nodes[node_index].leaf_object_id_plus_one = 0;

            // TODO: BVH STUFF
        }
    }
}