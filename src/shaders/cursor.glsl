@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;

void main() {
    gl_Position = mvp * vec4(pos.xy, 0.0, 1.0);
}
@end

@fs fs
layout(binding = 1) uniform fs_params {
    float time;
};

out vec4 frag_color;
void main() {
    float alpha = abs(sin(time / 200));
    frag_color = vec4(1.0, 1.0, 1.0, alpha);
}
@end

@program cursor vs fs
