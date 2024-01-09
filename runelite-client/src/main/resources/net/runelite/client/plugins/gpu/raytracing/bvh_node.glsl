struct BVHNode {
    // NOTE: The placement of the vec3 components is important here.
    // We want no padding to reduce the total size of this struct, and since it would pad up to vec4 size, we put a uint after the vec3 in place of the would-be padding
    ivec3 aabb_min;
    uint parent_index;

    ivec3 aabb_max;
    uint left_child_index;

    uint right_child_index;
    uint leaf_object_id_plus_one; // if this node is a leaf this will be != 0
    uint thread_counter;
    uint _unused; // To pad up to 12*4 bytes (may not be needed?)
};