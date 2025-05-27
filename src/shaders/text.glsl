@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 uv0;

out vec2 uv;
void main() {
    gl_Position = mvp * vec4(pos, 0.0, 1.0);
    uv = uv0;
}
@end

@fs fs
layout(binding = 1) uniform fs_params { 
    vec4 color;
};
layout(binding = 2) uniform texture2D tex; 
layout(binding = 3) uniform sampler tex_smp; 

in vec2 uv;

out vec4 frag_color;

void main() {
    float a = texture(sampler2D(tex, tex_smp), uv).r;
    frag_color = vec4(color.rgb, color.a * a);
}
@end

@program text vs fs
