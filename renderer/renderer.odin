package renderer

import gl "vendor:OpenGL"
import "core:fmt"
import eng "../engine"

// =============================================================================
// Directional Light
// =============================================================================

DirLight :: struct {
	direction: eng.Vec3,
	color:     eng.Vec3,
	ambient:   eng.Vec3,
}

DEFAULT_LIGHT :: DirLight{
	direction = {-0.5, -1.0, -0.3},
	color     = {1.0, 0.98, 0.92},
	ambient   = {0.05, 0.05, 0.08},
}

// =============================================================================
// Per-frame UBO data (std140 layout — Vec3s padded to Vec4)
// =============================================================================

@(private)
_FrameUniforms :: struct #align(16) {
	view:       eng.Mat4,   // 64 bytes
	projection: eng.Mat4,   // 64 bytes
	viewPos:    eng.Vec4,   // 16 bytes (padded from Vec3)
	lightDir:   eng.Vec4,   // 16 bytes (padded from Vec3)
	lightColor: eng.Vec4,   // 16 bytes (padded from Vec3)
	ambient:    eng.Vec4,   // 16 bytes (padded from Vec3)
}

// =============================================================================
// Renderer
// =============================================================================

Renderer :: struct {
	defaultShader:   Shader,
	instancedShader: Shader, // for GPU-instanced draws
	overlayShader:   Shader, // for simple screen-space editor overlays
	clearColor:      eng.Vec4,
	light:           DirLight,

	// Cached per-frame matrices, set in Renderer_Begin.
	viewMat:  eng.Mat4,
	projMat:  eng.Mat4,
	viewPos:  eng.Vec3,

	frameUBO: u32, // GL buffer handle for per-frame uniform block

	// Debug overlays
	grid:      Grid,
	gridReady: bool,
	overlayQuad: Mesh,
}

// Creates the built-in shaders, frame UBO, and optional debug grid.
Renderer_Init :: proc(renderer: ^Renderer) -> bool {
	shader, ok := Shader_Create(_VERT_SRC, _FRAG_SRC)
	if !ok {
		fmt.eprintln("[Renderer] Failed to compile default shader.")
		return false
	}
	renderer.defaultShader = shader
	renderer.clearColor    = {0.1, 0.1, 0.15, 1.0}
	renderer.light         = DEFAULT_LIGHT

	// Compile instancing shader.
	iShader, iOk := Shader_Create(_INSTANCED_VERT_SRC, _INSTANCED_FRAG_SRC)
	if !iOk {
		fmt.eprintln("[Renderer] Failed to compile instancing shader.")
		Shader_Destroy(&renderer.defaultShader)
		return false
	}
	renderer.instancedShader = iShader

	overlayShader, overlayOk := Shader_Create(_OVERLAY_VERT_SRC, _OVERLAY_FRAG_SRC)
	if !overlayOk {
		fmt.eprintln("[Renderer] Failed to compile overlay shader.")
		Shader_Destroy(&renderer.instancedShader)
		Shader_Destroy(&renderer.defaultShader)
		return false
	}
	renderer.overlayShader = overlayShader

	overlayQuad, quadOk := Mesh_Create_Quad()
	if !quadOk {
		fmt.eprintln("[Renderer] Failed to create overlay quad.")
		Shader_Destroy(&renderer.overlayShader)
		Shader_Destroy(&renderer.instancedShader)
		Shader_Destroy(&renderer.defaultShader)
		return false
	}
	renderer.overlayQuad = overlayQuad

	// Create per-frame UBO at binding point 0.
	gl.GenBuffers(1, &renderer.frameUBO)
	gl.BindBuffer(gl.UNIFORM_BUFFER, renderer.frameUBO)
	gl.BufferData(gl.UNIFORM_BUFFER, size_of(_FrameUniforms), nil, gl.DYNAMIC_DRAW)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, renderer.frameUBO)
	gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

	// Bind both shaders' uniform blocks to binding point 0.
	blockIdx := gl.GetUniformBlockIndex(renderer.defaultShader.id, "FrameUniforms")
	if blockIdx != gl.INVALID_INDEX {
		gl.UniformBlockBinding(renderer.defaultShader.id, blockIdx, 0)
	}
	iBlockIdx := gl.GetUniformBlockIndex(renderer.instancedShader.id, "FrameUniforms")
	if iBlockIdx != gl.INVALID_INDEX {
		gl.UniformBlockBinding(renderer.instancedShader.id, iBlockIdx, 0)
	}

	cfg := eng.Get_Config()
	if cfg.debug.showGrid {
		renderer.gridReady = Grid_Init(&renderer.grid)
		if !renderer.gridReady {
			fmt.eprintln("[Renderer] Grid init failed — continuing without grid.")
		}
	}

	return true
}

// Releases all renderer-owned GPU resources.
Renderer_Shutdown :: proc(renderer: ^Renderer) {
	if renderer.gridReady do Grid_Destroy(&renderer.grid)
	gl.DeleteBuffers(1, &renderer.frameUBO)
	Mesh_Destroy(&renderer.overlayQuad)
	Shader_Destroy(&renderer.overlayShader)
	Shader_Destroy(&renderer.instancedShader)
	Shader_Destroy(&renderer.defaultShader)
}

// Call at the start of each frame before any draw calls.
Renderer_Begin :: proc(renderer: ^Renderer, cam: ^eng.Camera, aspect: f32) {
	renderer.viewMat = eng.Camera_Get_View(cam)
	renderer.projMat = eng.Camera_Get_Projection(cam, aspect)
	renderer.viewPos = cam.position

	gl.ClearColor(
		renderer.clearColor.r,
		renderer.clearColor.g,
		renderer.clearColor.b,
		renderer.clearColor.a,
	)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

	Shader_Bind(&renderer.defaultShader)

	frameData := _FrameUniforms{
		view       = renderer.viewMat,
		projection = renderer.projMat,
		viewPos    = {renderer.viewPos.x, renderer.viewPos.y, renderer.viewPos.z, 0},
		lightDir   = {renderer.light.direction.x, renderer.light.direction.y, renderer.light.direction.z, 0},
		lightColor = {renderer.light.color.x, renderer.light.color.y, renderer.light.color.z, 0},
		ambient    = {renderer.light.ambient.x, renderer.light.ambient.y, renderer.light.ambient.z, 0},
	}
	gl.BindBuffer(gl.UNIFORM_BUFFER, renderer.frameUBO)
	gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(_FrameUniforms), &frameData)
	gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
}

// Call at the end of each frame.
Renderer_End :: proc(renderer: ^Renderer) {
	Shader_Unbind()
}

// Draw the debug grid. Call after all opaque geometry, before Renderer_End.
// No-op if showGrid is false or grid failed to init.
Renderer_Draw_Grid :: proc(renderer: ^Renderer) {
	if !renderer.gridReady do return

	cfg := eng.Get_Config()
	if !cfg.debug.showGrid do return

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Disable(gl.CULL_FACE)

	Grid_Draw(&renderer.grid, renderer.viewPos, cfg.debug)

	gl.Disable(gl.BLEND)
	gl.Enable(gl.CULL_FACE)
}

// Draw a mesh with a model matrix and a solid RGB colour.
Renderer_Draw_Mesh :: proc(renderer: ^Renderer, mesh: ^Mesh, model: eng.Mat4, color: eng.Vec3 = {1, 1, 1}) {
	normalMat := eng.Mat4_Normal(model)
	modelCopy := model
	Shader_Set_Mat4(&renderer.defaultShader, "uModel",        &modelCopy)
	Shader_Set_Mat4(&renderer.defaultShader, "uNormalMatrix", &normalMat)
	Shader_Set_Vec3(&renderer.defaultShader, "uColor",        color)
	Mesh_Draw(mesh)
}

// Draw a mesh using a Transform struct.
Renderer_Draw_Transform :: proc(renderer: ^Renderer, mesh: ^Mesh, transform: eng.Transform, color: eng.Vec3 = {1, 1, 1}) {
	model := eng.Transform_To_Mat4(transform)
	Renderer_Draw_Mesh(renderer, mesh, model, color)
}

// Sets the clear color used by Renderer_Begin.
Renderer_Set_Clear_Color :: proc(renderer: ^Renderer, color: eng.Vec4) {
	renderer.clearColor = color
}

// Sets the active directional light parameters.
Renderer_Set_Light :: proc(renderer: ^Renderer, light: DirLight) {
	renderer.light = light
}

// Binds a shader program for manual draw work.
Renderer_Use_Shader :: proc(renderer: ^Renderer, shader: ^Shader) {
	Shader_Bind(shader)
}

// Rebinds the renderer's default mesh shader.
Renderer_Use_Default_Shader :: proc(renderer: ^Renderer) {
	Shader_Bind(&renderer.defaultShader)
}

// Draw a batch of instances in a single draw call.
// Binds the instancing shader, uploads instance data, draws, then restores the default shader.
// Call between Renderer_Begin and Renderer_End.
Renderer_Draw_Instanced :: proc(renderer: ^Renderer, mesh: ^Mesh, instances: []InstanceData) {
	if len(instances) == 0 do return
	Shader_Bind(&renderer.instancedShader)
	Mesh_Draw_Instanced(mesh, instances)
	Shader_Bind(&renderer.defaultShader)
}

// Draws a solid rectangle in screen pixel coordinates.
// Intended for lightweight editor overlays such as marquee selection.
Renderer_Draw_Screen_Rect :: proc(renderer: ^Renderer, screenSize, min, max: eng.Vec2, color: eng.Vec4) {
	width  := max.x - min.x
	height := max.y - min.y
	if width <= 0 || height <= 0 do return

	_overlay_begin(renderer, screenSize)
	_overlay_draw_rect(renderer, min, max, color)
	_overlay_end(renderer)
}

// Draws a translucent marquee with a crisp border.
Renderer_Draw_Marquee :: proc(renderer: ^Renderer, screenSize, p0, p1: eng.Vec2) {
	min := eng.Vec2{min(p0.x, p1.x), min(p0.y, p1.y)}
	max := eng.Vec2{max(p0.x, p1.x), max(p0.y, p1.y)}
	if max.x - min.x <= 0 || max.y - min.y <= 0 do return

	border := f32(2.0)
	fillColor   := eng.Vec4{1.0, 0.85, 0.0, 0.18}
	borderColor := eng.Vec4{1.0, 0.92, 0.35, 0.95}

	_overlay_begin(renderer, screenSize)
	_overlay_draw_rect(renderer, min, max, fillColor)
	_overlay_draw_rect(renderer, min, {max.x, min.y + border}, borderColor)
	_overlay_draw_rect(renderer, {min.x, max.y - border}, max, borderColor)
	_overlay_draw_rect(renderer, min, {min.x + border, max.y}, borderColor)
	_overlay_draw_rect(renderer, {max.x - border, min.y}, max, borderColor)
	_overlay_end(renderer)
}

_overlay_begin :: proc(renderer: ^Renderer, screenSize: eng.Vec2) {
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Disable(gl.CULL_FACE)

	Shader_Bind(&renderer.overlayShader)
	Shader_Set_Vec2(&renderer.overlayShader, "uScreenSize", screenSize)
}

_overlay_draw_rect :: proc(renderer: ^Renderer, min, max: eng.Vec2, color: eng.Vec4) {
	width  := max.x - min.x
	height := max.y - min.y
	if width <= 0 || height <= 0 do return

	Shader_Set_Vec4(&renderer.overlayShader, "uRect", {min.x, min.y, width, height})
	Shader_Set_Vec4(&renderer.overlayShader, "uColor", color)
	Mesh_Draw(&renderer.overlayQuad)
}

_overlay_end :: proc(renderer: ^Renderer) {
	gl.Disable(gl.BLEND)
	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.DEPTH_TEST)
	Shader_Bind(&renderer.defaultShader)
}

// =============================================================================
// Built-in Blinn-Phong Shader Source
// =============================================================================

@(private)
_VERT_SRC :: `#version 410 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;

layout(std140) uniform FrameUniforms {
    mat4 uView;
    mat4 uProjection;
    vec4 uViewPos;
    vec4 uLightDir;
    vec4 uLightColor;
    vec4 uAmbient;
};

uniform mat4 uModel;
uniform mat4 uNormalMatrix;

out vec3 vFragPos;
out vec3 vNormal;
out vec2 vUV;

void main() {
    vec4 worldPos  = uModel * vec4(aPos, 1.0);
    vFragPos       = worldPos.xyz;
    vNormal        = normalize(mat3(uNormalMatrix) * aNormal);
    vUV            = aUV;
    gl_Position    = uProjection * uView * worldPos;
}
`

@(private)
_FRAG_SRC :: `#version 410 core

in vec3 vFragPos;
in vec3 vNormal;
in vec2 vUV;

layout(std140) uniform FrameUniforms {
    mat4 uView;
    mat4 uProjection;
    vec4 uViewPos;
    vec4 uLightDir;
    vec4 uLightColor;
    vec4 uAmbient;
};

uniform vec3 uColor;

out vec4 fragColor;

void main() {
    vec3 normal   = normalize(vNormal);
    vec3 lightDir = normalize(-uLightDir.xyz);

    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * uLightColor.xyz;

    vec3  viewDir  = normalize(uViewPos.xyz - vFragPos);
    vec3  halfDir  = normalize(lightDir + viewDir);
    float spec     = pow(max(dot(normal, halfDir), 0.0), 32.0);
    vec3  specular = spec * uLightColor.xyz * 0.3;

    vec3 result = (uAmbient.xyz + diffuse + specular) * uColor;
    fragColor   = vec4(result, 1.0);
}
`

// =============================================================================
// Instancing Shader Source
// Per-instance attributes (divisor 1) at locations 3-7:
//   3-6: model matrix columns (vec4 each)
//   7:   colour (vec4, w unused)
// NOTE: normals are transformed with mat3(model) — correct only for uniform scale.
// =============================================================================

@(private)
_INSTANCED_VERT_SRC :: `#version 410 core

// Per-vertex (divisor 0)
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;

// Per-instance (divisor 1)
layout(location = 3) in vec4 iModelCol0;
layout(location = 4) in vec4 iModelCol1;
layout(location = 5) in vec4 iModelCol2;
layout(location = 6) in vec4 iModelCol3;
layout(location = 7) in vec4 iColor;

layout(std140) uniform FrameUniforms {
    mat4 uView;
    mat4 uProjection;
    vec4 uViewPos;
    vec4 uLightDir;
    vec4 uLightColor;
    vec4 uAmbient;
};

out vec3 vFragPos;
out vec3 vNormal;
out vec2 vUV;
out vec3 vColor;

void main() {
    mat4 model  = mat4(iModelCol0, iModelCol1, iModelCol2, iModelCol3);
    vec4 worldPos = model * vec4(aPos, 1.0);
    vFragPos    = worldPos.xyz;
    vNormal     = normalize(mat3(model) * aNormal);
    vUV         = aUV;
    vColor      = iColor.rgb;
    gl_Position = uProjection * uView * worldPos;
}
`

@(private)
_INSTANCED_FRAG_SRC :: `#version 410 core

in vec3 vFragPos;
in vec3 vNormal;
in vec2 vUV;
in vec3 vColor;

layout(std140) uniform FrameUniforms {
    mat4 uView;
    mat4 uProjection;
    vec4 uViewPos;
    vec4 uLightDir;
    vec4 uLightColor;
    vec4 uAmbient;
};

out vec4 fragColor;

void main() {
    vec3 normal   = normalize(vNormal);
    vec3 lightDir = normalize(-uLightDir.xyz);

    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * uLightColor.xyz;

    vec3  viewDir  = normalize(uViewPos.xyz - vFragPos);
    vec3  halfDir  = normalize(lightDir + viewDir);
    float spec     = pow(max(dot(normal, halfDir), 0.0), 32.0);
    vec3  specular = spec * uLightColor.xyz * 0.3;

    vec3 result = (uAmbient.xyz + diffuse + specular) * vColor;
    fragColor   = vec4(result, 1.0);
}
`

@(private)
_OVERLAY_VERT_SRC :: `#version 410 core

layout(location = 0) in vec3 aPos;

uniform vec2 uScreenSize;
uniform vec4 uRect;

void main() {
    vec2 uv    = aPos.xy + vec2(0.5, 0.5);
    vec2 pixel = uRect.xy + uv * uRect.zw;
    vec2 ndc   = vec2(
        (pixel.x / uScreenSize.x) * 2.0 - 1.0,
        1.0 - (pixel.y / uScreenSize.y) * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
}
`

@(private)
_OVERLAY_FRAG_SRC :: `#version 410 core

uniform vec4 uColor;

out vec4 fragColor;

void main() {
    fragColor = uColor;
}
`
