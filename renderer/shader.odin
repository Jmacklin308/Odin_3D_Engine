package renderer

import gl "vendor:OpenGL"
import "core:fmt"
import "core:os"

// =============================================================================
// Shader
// A compiled and linked OpenGL shader program.
// =============================================================================

Shader :: struct {
	id:       u32,            // OpenGL program handle. 0 = invalid / not compiled.
	uniforms: map[cstring]i32, // Cached uniform locations.
}

// Compile a shader program from GLSL source strings.
Shader_Create :: proc(vertSrc, fragSrc: string) -> (shader: Shader, ok: bool) {
	vertId, vertOk := _compile_stage(gl.VERTEX_SHADER, vertSrc)
	if !vertOk do return {}, false

	fragId, fragOk := _compile_stage(gl.FRAGMENT_SHADER, fragSrc)
	if !fragOk {
		gl.DeleteShader(vertId)
		return {}, false
	}

	progId := gl.CreateProgram()
	gl.AttachShader(progId, vertId)
	gl.AttachShader(progId, fragId)
	gl.LinkProgram(progId)

	gl.DeleteShader(vertId)
	gl.DeleteShader(fragId)

	success: i32
	gl.GetProgramiv(progId, gl.LINK_STATUS, &success)
	if success == 0 {
		logLen: i32
		gl.GetProgramiv(progId, gl.INFO_LOG_LENGTH, &logLen)
		logBuf := make([]u8, logLen, context.temp_allocator)
		gl.GetProgramInfoLog(progId, logLen, nil, raw_data(logBuf))
		fmt.eprintf("[Shader] Link error: %s\n", string(logBuf))
		gl.DeleteProgram(progId)
		return {}, false
	}

	shader.id       = progId
	shader.uniforms = make(map[cstring]i32)
	return shader, true
}

// Load GLSL source from files on disk and compile.
Shader_Load_Files :: proc(vertPath, fragPath: string) -> (shader: Shader, ok: bool) {
	vertBytes, vertRead := os.read_entire_file(vertPath)
	if !vertRead {
		fmt.eprintf("[Shader] Could not read vertex shader: %s\n", vertPath)
		return {}, false
	}
	defer delete(vertBytes)

	fragBytes, fragRead := os.read_entire_file(fragPath)
	if !fragRead {
		fmt.eprintf("[Shader] Could not read fragment shader: %s\n", fragPath)
		return {}, false
	}
	defer delete(fragBytes)

	return Shader_Create(string(vertBytes), string(fragBytes))
}

Shader_Destroy :: proc(shader: ^Shader) {
	if shader.id != 0 {
		delete(shader.uniforms)
		gl.DeleteProgram(shader.id)
		shader.id = 0
	}
}

Shader_Bind :: proc(shader: ^Shader) {
	gl.UseProgram(shader.id)
}

Shader_Unbind :: proc() {
	gl.UseProgram(0)
}

// =============================================================================
// Uniform Setters
// =============================================================================

Shader_Set_Int :: proc(shader: ^Shader, name: cstring, val: i32) {
	loc := _shader_get_loc(shader, name)
	gl.Uniform1i(loc, val)
}

Shader_Set_Float :: proc(shader: ^Shader, name: cstring, val: f32) {
	loc := _shader_get_loc(shader, name)
	gl.Uniform1f(loc, val)
}

Shader_Set_Vec2 :: proc(shader: ^Shader, name: cstring, val: [2]f32) {
	loc := _shader_get_loc(shader, name)
	gl.Uniform2f(loc, val.x, val.y)
}

Shader_Set_Vec3 :: proc(shader: ^Shader, name: cstring, val: [3]f32) {
	loc := _shader_get_loc(shader, name)
	gl.Uniform3f(loc, val.x, val.y, val.z)
}

Shader_Set_Vec4 :: proc(shader: ^Shader, name: cstring, val: [4]f32) {
	loc := _shader_get_loc(shader, name)
	gl.Uniform4f(loc, val.x, val.y, val.z, val.w)
}

Shader_Set_Mat4 :: proc(shader: ^Shader, name: cstring, val: ^matrix[4, 4]f32) {
	loc := _shader_get_loc(shader, name)
	gl.UniformMatrix4fv(loc, 1, gl.FALSE, &val[0, 0])
}

// =============================================================================
// Internal
// =============================================================================

@(private)
_shader_get_loc :: proc(shader: ^Shader, name: cstring) -> i32 {
	if loc, ok := shader.uniforms[name]; ok do return loc
	loc := gl.GetUniformLocation(shader.id, name)
	shader.uniforms[name] = loc
	return loc
}

@(private)
_compile_stage :: proc(stageType: u32, src: string) -> (id: u32, ok: bool) {
	id = gl.CreateShader(stageType)

	srcCStr := cstring(raw_data(src))
	srcLen  := i32(len(src))
	gl.ShaderSource(id, 1, &srcCStr, &srcLen)
	gl.CompileShader(id)

	success: i32
	gl.GetShaderiv(id, gl.COMPILE_STATUS, &success)
	if success == 0 {
		logLen: i32
		gl.GetShaderiv(id, gl.INFO_LOG_LENGTH, &logLen)
		logBuf := make([]u8, logLen, context.temp_allocator)
		gl.GetShaderInfoLog(id, logLen, nil, raw_data(logBuf))
		stageName := stageType == gl.VERTEX_SHADER ? "vertex" : "fragment"
		fmt.eprintf("[Shader] %s compile error:\n%s\n", stageName, string(logBuf))
		gl.DeleteShader(id)
		return 0, false
	}

	return id, true
}
