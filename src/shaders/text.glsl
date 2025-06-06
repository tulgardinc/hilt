@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs
@glsl_options flip_vert_y

layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 uv_in;

in vec2 offset;
in vec2 dims;
in vec4 uv_rect_in;
in vec4 col_in;

out vec2 uv;
out vec4 uv_rect;
out vec4 col;
out vec2 frag_pos;
void main() {
    uv = uv_in;
    uv_rect = uv_rect_in;
    col = col_in;
    vec2 transformed_pos = dims * pos + offset;
    
    vec4 world_position = vec4(transformed_pos, 0.0, 1.0);
    gl_Position = mvp * world_position;
    frag_pos = world_position.xy;
}
@end

@fs fs
in vec2 uv;
in vec4 uv_rect;
in vec4 col;
in vec2 frag_pos;

layout(binding = 1) uniform texture2D tex;
layout(binding = 2) uniform sampler smp;
layout(binding = 3) uniform fs_params {
    vec2 cursor_position;
    vec2 cursor_dimensions;
};

out vec4 frag_color;
void main() {
    vec2 vert_uv = uv_rect.zw * uv + uv_rect.xy;
    float val = texture(sampler2D(tex, smp), vert_uv).r;

    bool cursor_overlap = 
        frag_pos.x >= cursor_position.x && frag_pos.x <= cursor_position.x + cursor_dimensions.x &&
        frag_pos.y <= cursor_position.y && frag_pos.y >= cursor_position.y - cursor_dimensions.y;

    frag_color = cursor_overlap ? vec4(0.0, 0.0, 0.0, val) : vec4(col.xyz, val);
}
@end

@program text vs fs
