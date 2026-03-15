package renderer

import gl  "vendor:OpenGL"
import "core:fmt"
import eng "../engine"

// =============================================================================
// Debug Grid
//
// Infinite-looking XZ grid rendered via a single flat quad and a fragment
// shader that computes 1m grid lines analytically using screen-space
// derivatives (fwidth). The quad follows the camera on XZ so it always fills
// the visible ground plane. Configured via eng.DebugConfig.
// =============================================================================

Grid :: struct {
	shader: Shader,
	vao:    u32,
	vbo:    u32,
}

// Creates the debug grid shader and geometry.
Grid_Init :: proc(grid: ^Grid) -> bool {
	shader, ok := Shader_Create(_GRID_VERT_SRC, _GRID_FRAG_SRC)
	if !ok {
		fmt.eprintln("[Grid] Failed to compile grid shader.")
		return false
	}
	grid.shader = shader

	// Bind the grid shader's uniform block to binding point 0.
	blockIdx := gl.GetUniformBlockIndex(grid.shader.id, "FrameUniforms")
	if blockIdx != gl.INVALID_INDEX {
		gl.UniformBlockBinding(grid.shader.id, blockIdx, 0)
	}

	// A unit XZ quad (Y = 0). Scaled by uHalfExtent in the vertex shader.
	// Triangle-strip order: TL, TR, BL, BR → two triangles, no index buffer.
	positions := [4][3]f32{
		{-1, 0, -1},
		{ 1, 0, -1},
		{-1, 0,  1},
		{ 1, 0,  1},
	}

	gl.GenVertexArrays(1, &grid.vao)
	gl.GenBuffers(1, &grid.vbo)
	gl.BindVertexArray(grid.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, grid.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(positions), &positions[0], gl.STATIC_DRAW)

	// location 0: vec3 — stride 12 bytes, offset 0
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 12, 0)
	gl.EnableVertexAttribArray(0)

	fmt.println("[Grid] Initialised.")
	return true
}

// Draws the debug grid using the current frame uniforms.
Grid_Draw :: proc(grid: ^Grid, cameraPos: eng.Vec3, cfg: eng.DebugConfig) {
	Shader_Bind(&grid.shader)

	Shader_Set_Float (&grid.shader, "uHalfExtent", cfg.gridHalfExtent)
	Shader_Set_Vec3  (&grid.shader, "uCameraPos",  cameraPos)
	Shader_Set_Vec4  (&grid.shader, "uGridColor",  cfg.gridColor)
	Shader_Set_Float (&grid.shader, "uFadeStart",  cfg.gridFadeStart)
	Shader_Set_Float (&grid.shader, "uFadeEnd",    cfg.gridFadeEnd)

	gl.BindVertexArray(grid.vao)
	gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

	Shader_Unbind()
}

// Destroys the debug grid shader and buffers.
Grid_Destroy :: proc(grid: ^Grid) {
	if grid.vbo != 0 do gl.DeleteBuffers(1, &grid.vbo)
	if grid.vao != 0 do gl.DeleteVertexArrays(1, &grid.vao)
	Shader_Destroy(&grid.shader)
	grid^ = {}
}

// =============================================================================
// Grid Shader Source
// =============================================================================

@(private)
_GRID_VERT_SRC :: `#version 410 core

layout(location = 0) in vec3 aPos;

layout(std140) uniform FrameUniforms {
    mat4 uView;
    mat4 uProjection;
    vec4 uViewPos;
    vec4 uLightDir;
    vec4 uLightColor;
    vec4 uAmbient;
};

uniform float uHalfExtent;
uniform vec3  uCameraPos;

out vec3 vWorldPos;

void main() {
    // Scale unit quad to half-extent and snap centre to camera XZ.
    // Y stays at 0 — the grid always lies on the world origin plane.
    vec3 worldPos = vec3(
        aPos.x * uHalfExtent + uCameraPos.x,
        0.0,
        aPos.z * uHalfExtent + uCameraPos.z
    );
    vWorldPos   = worldPos;
    gl_Position = uProjection * uView * vec4(worldPos, 1.0);
}
`

@(private)
_GRID_FRAG_SRC :: `#version 410 core

in  vec3 vWorldPos;
out vec4 fragColor;

uniform vec4  uGridColor;
uniform float uFadeStart;
uniform float uFadeEnd;
uniform vec3  uCameraPos;

void main() {
    // Compute distance to nearest 1m grid line on XZ using screen-space
    // derivatives for anti-aliasing. fwidth gives pixel footprint in world
    // space, making line width constant in screen pixels regardless of zoom.
    vec2  coord    = vWorldPos.xz;
    vec2  grid     = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
    float lineMask = 1.0 - min(min(grid.x, grid.y), 1.0);

    // Discard fragments that aren't on a line to avoid depth writes on the
    // empty quad area.
    if (lineMask < 0.01) discard;

    // Fade lines out by XZ distance from the camera.
    float dist  = length(vWorldPos.xz - uCameraPos.xz);
    float alpha = 1.0 - smoothstep(uFadeStart, uFadeEnd, dist);

    fragColor = vec4(uGridColor.rgb, uGridColor.a * alpha * lineMask);
}
`
