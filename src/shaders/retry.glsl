@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs

layout(binding = 2) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 uv0;

out vec2 uv;
void main() {
    uv = uv0;
    gl_Position = mvp * vec4(pos.xy, 0.0, 1.0);
}
@end

@fs fs
in vec2 uv;

layout(binding = 0) uniform texture2D tex;
layout(binding = 1) uniform sampler smp;

out vec4 frag_color;
void main() {
    float val = texture(sampler2D(tex, smp), uv).r;
    frag_color = vec4(1.0, 1.0, 1.0, val);
}
@end

@program retry vs fs
