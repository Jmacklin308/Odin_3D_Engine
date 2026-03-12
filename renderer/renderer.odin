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
// Renderer
// =============================================================================

Renderer :: struct {
	defaultShader: Shader,
	clearColor:    eng.Vec4,
	light:         DirLight,

	// Cached per-frame matrices, set in Renderer_Begin.
	viewMat:  eng.Mat4,
	projMat:  eng.Mat4,
	viewPos:  eng.Vec3,
}

Renderer_Init :: proc(renderer: ^Renderer) -> bool {
	shader, ok := Shader_Create(_VERT_SRC, _FRAG_SRC)
	if !ok {
		fmt.eprintln("[Renderer] Failed to compile default shader.")
		return false
	}
	renderer.defaultShader = shader
	renderer.clearColor    = {0.1, 0.1, 0.15, 1.0}
	renderer.light         = DEFAULT_LIGHT
	return true
}

Renderer_Shutdown :: proc(renderer: ^Renderer) {
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
	Shader_Set_Mat4(&renderer.defaultShader, "uView",       &renderer.viewMat)
	Shader_Set_Mat4(&renderer.defaultShader, "uProjection", &renderer.projMat)
	Shader_Set_Vec3(&renderer.defaultShader, "uViewPos",    renderer.viewPos)
	Shader_Set_Vec3(&renderer.defaultShader, "uLightDir",   renderer.light.direction)
	Shader_Set_Vec3(&renderer.defaultShader, "uLightColor", renderer.light.color)
	Shader_Set_Vec3(&renderer.defaultShader, "uAmbient",    renderer.light.ambient)
}

// Call at the end of each frame.
Renderer_End :: proc(renderer: ^Renderer) {
	Shader_Unbind()
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

Renderer_Set_Clear_Color :: proc(renderer: ^Renderer, color: eng.Vec4) {
	renderer.clearColor = color
}

Renderer_Set_Light :: proc(renderer: ^Renderer, light: DirLight) {
	renderer.light = light
}

Renderer_Use_Shader :: proc(renderer: ^Renderer, shader: ^Shader) {
	Shader_Bind(shader)
}

Renderer_Use_Default_Shader :: proc(renderer: ^Renderer) {
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

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;
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

uniform vec3 uColor;
uniform vec3 uLightDir;
uniform vec3 uLightColor;
uniform vec3 uAmbient;
uniform vec3 uViewPos;

out vec4 fragColor;

void main() {
    vec3 normal   = normalize(vNormal);
    vec3 lightDir = normalize(-uLightDir);

    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * uLightColor;

    vec3  viewDir  = normalize(uViewPos - vFragPos);
    vec3  halfDir  = normalize(lightDir + viewDir);
    float spec     = pow(max(dot(normal, halfDir), 0.0), 32.0);
    vec3  specular = spec * uLightColor * 0.3;

    vec3 result = (uAmbient + diffuse + specular) * uColor;
    fragColor   = vec4(result, 1.0);
}
`
