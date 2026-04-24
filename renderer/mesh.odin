package renderer

import gl "vendor:OpenGL"
import "core:fmt"
import "core:math"
import eng "../engine"

// =============================================================================
// Vertex Layout
// 32 bytes, packed. Layout matches attribute locations in the default shader:
//   location 0 = pos, 1 = normal, 2 = uv
// =============================================================================

Vertex :: struct #packed {
	pos:    eng.Vec3, // offset  0 — 12 bytes
	normal: eng.Vec3, // offset 12 — 12 bytes
	uv:     eng.Vec2, // offset 24 —  8 bytes
}             //           total: 32 bytes

#assert(size_of(Vertex) == 32)

// =============================================================================
// Mesh
// =============================================================================

Mesh :: struct {
	vao:         u32,
	vbo:         u32,
	ebo:         u32,
	instanceVBO: u32, // 0 = instancing not enabled
	indexCount:  i32,
	vertexCount: i32,
	indexed:     bool,
}

// Per-instance data uploaded to the GPU each frame.
// Contains the model matrix (as 4 column vectors) and a solid colour.
// Note: instanced rendering requires uniform scale — normals are transformed
// with mat3(model). Add a normal matrix field if non-uniform scale is needed.
InstanceData :: struct {
	modelCol0: eng.Vec4, // column 0 of model matrix
	modelCol1: eng.Vec4, // column 1
	modelCol2: eng.Vec4, // column 2
	modelCol3: eng.Vec4, // column 3 (translation)
	color:     eng.Vec4, // rgb + padding
} // 80 bytes

// Build InstanceData from a Transform and a solid colour.
Instance_Data_From_Transform :: proc(t: eng.Transform, color: eng.Vec3) -> InstanceData {
	m := eng.Transform_To_Mat4(t)
	return InstanceData{
		// Odin matrix[4,4]f32 is column-major: m[row, col].
		// Each modelColN is one column of the matrix.
		modelCol0 = {m[0, 0], m[1, 0], m[2, 0], m[3, 0]},
		modelCol1 = {m[0, 1], m[1, 1], m[2, 1], m[3, 1]},
		modelCol2 = {m[0, 2], m[1, 2], m[2, 2], m[3, 2]},
		modelCol3 = {m[0, 3], m[1, 3], m[2, 3], m[3, 3]},
		color     = {color.x, color.y, color.z, 1},
	}
}

// Creates a GPU mesh from vertex data and optional indices.
Mesh_Create :: proc(vertices: []Vertex, indices: []u32 = nil) -> (mesh: Mesh, ok: bool) {
	if len(vertices) == 0 {
		fmt.eprintln("[Mesh] Cannot create a mesh with zero vertices. Nice try.")
		return {}, false
	}

	gl.GenVertexArrays(1, &mesh.vao)
	gl.GenBuffers(1, &mesh.vbo)
	gl.BindVertexArray(mesh.vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(Vertex),
		raw_data(vertices),
		gl.STATIC_DRAW,
	)

	if len(indices) > 0 {
		gl.GenBuffers(1, &mesh.ebo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
		gl.BufferData(
			gl.ELEMENT_ARRAY_BUFFER,
			len(indices) * size_of(u32),
			raw_data(indices),
			gl.STATIC_DRAW,
		)
		mesh.indexCount = i32(len(indices))
		mesh.indexed    = true
	}

	// Position — location 0
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(0)

	// Normal — location 1
	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, normal))
	gl.EnableVertexAttribArray(1)

	// UV — location 2
	gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, uv))
	gl.EnableVertexAttribArray(2)

	gl.BindVertexArray(0)
	mesh.vertexCount = i32(len(vertices))

	return mesh, true
}

// Destroys the GPU buffers owned by the mesh.
Mesh_Destroy :: proc(mesh: ^Mesh) {
	if mesh.ebo         != 0 do gl.DeleteBuffers(1, &mesh.ebo)
	if mesh.instanceVBO != 0 do gl.DeleteBuffers(1, &mesh.instanceVBO)
	if mesh.vbo         != 0 do gl.DeleteBuffers(1, &mesh.vbo)
	if mesh.vao         != 0 do gl.DeleteVertexArrays(1, &mesh.vao)
	mesh^ = {}
}

// Enable instanced rendering on an existing mesh.
// Allocates a GPU buffer sized for maxInstances * size_of(InstanceData).
// Registers instance attributes at locations 3-7 with divisor 1.
// Call once after Mesh_Create; safe to call again (no-op if already enabled).
Mesh_Enable_Instancing :: proc(mesh: ^Mesh, maxInstances: int) -> bool {
	if mesh.instanceVBO != 0 do return true // already set up

	gl.BindVertexArray(mesh.vao)
	gl.GenBuffers(1, &mesh.instanceVBO)
	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.instanceVBO)
	gl.BufferData(gl.ARRAY_BUFFER, maxInstances * size_of(InstanceData), nil, gl.DYNAMIC_DRAW)

	stride := i32(size_of(InstanceData))
	// Locations 3-6: model matrix columns (one vec4 each)
	for col in 0 ..< 4 {
		loc := u32(3 + col)
		off := uintptr(col * size_of(eng.Vec4))
		gl.VertexAttribPointer(loc, 4, gl.FLOAT, gl.FALSE, stride, off)
		gl.EnableVertexAttribArray(loc)
		gl.VertexAttribDivisor(loc, 1)
	}
	// Location 7: colour (vec4)
	gl.VertexAttribPointer(7, 4, gl.FLOAT, gl.FALSE, stride, uintptr(4 * size_of(eng.Vec4)))
	gl.EnableVertexAttribArray(7)
	gl.VertexAttribDivisor(7, 1)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	return true
}

// Upload instance data and issue a single instanced draw call.
// Must be called with the instancing shader bound.
Mesh_Draw_Instanced :: proc(mesh: ^Mesh, instances: []InstanceData) {
	if mesh.instanceVBO == 0 || len(instances) == 0 do return

	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.instanceVBO)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		len(instances) * size_of(InstanceData),
		raw_data(instances),
	)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.BindVertexArray(mesh.vao)
	if mesh.indexed {
		gl.DrawElementsInstanced(
			gl.TRIANGLES,
			mesh.indexCount,
			gl.UNSIGNED_INT,
			nil,
			i32(len(instances)),
		)
	} else {
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, mesh.vertexCount, i32(len(instances)))
	}
	gl.BindVertexArray(0)
}

// Draws the mesh once with the currently bound shader.
Mesh_Draw :: proc(mesh: ^Mesh) {
	gl.BindVertexArray(mesh.vao)
	if mesh.indexed {
		gl.DrawElements(gl.TRIANGLES, mesh.indexCount, gl.UNSIGNED_INT, nil)
	} else {
		gl.DrawArrays(gl.TRIANGLES, 0, mesh.vertexCount)
	}
}

// Creates a unit cube centered at the origin.
Mesh_Create_Cube :: proc() -> (Mesh, bool) {
	vertices := [24]Vertex{
		// +X face
		{{+0.5, -0.5, -0.5}, {1, 0, 0}, {0, 0}},
		{{+0.5, +0.5, -0.5}, {1, 0, 0}, {0, 1}},
		{{+0.5, +0.5, +0.5}, {1, 0, 0}, {1, 1}},
		{{+0.5, -0.5, +0.5}, {1, 0, 0}, {1, 0}},
		// -X face
		{{-0.5, -0.5, +0.5}, {-1, 0, 0}, {0, 0}},
		{{-0.5, +0.5, +0.5}, {-1, 0, 0}, {0, 1}},
		{{-0.5, +0.5, -0.5}, {-1, 0, 0}, {1, 1}},
		{{-0.5, -0.5, -0.5}, {-1, 0, 0}, {1, 0}},
		// +Y face
		{{-0.5, +0.5, -0.5}, {0, 1, 0}, {0, 0}},
		{{-0.5, +0.5, +0.5}, {0, 1, 0}, {0, 1}},
		{{+0.5, +0.5, +0.5}, {0, 1, 0}, {1, 1}},
		{{+0.5, +0.5, -0.5}, {0, 1, 0}, {1, 0}},
		// -Y face
		{{-0.5, -0.5, +0.5}, {0, -1, 0}, {0, 0}},
		{{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 1}},
		{{+0.5, -0.5, -0.5}, {0, -1, 0}, {1, 1}},
		{{+0.5, -0.5, +0.5}, {0, -1, 0}, {1, 0}},
		// +Z face
		{{-0.5, -0.5, +0.5}, {0, 0, 1}, {0, 0}},
		{{+0.5, -0.5, +0.5}, {0, 0, 1}, {0, 1}},
		{{+0.5, +0.5, +0.5}, {0, 0, 1}, {1, 1}},
		{{-0.5, +0.5, +0.5}, {0, 0, 1}, {1, 0}},
		// -Z face
		{{+0.5, -0.5, -0.5}, {0, 0, -1}, {0, 0}},
		{{-0.5, -0.5, -0.5}, {0, 0, -1}, {0, 1}},
		{{-0.5, +0.5, -0.5}, {0, 0, -1}, {1, 1}},
		{{+0.5, +0.5, -0.5}, {0, 0, -1}, {1, 0}},
	}

	indices := [36]u32{
		 0,  1,  2,  0,  2,  3,
		 4,  5,  6,  4,  6,  7,
		 8,  9, 10,  8, 10, 11,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 21, 22, 20, 22, 23,
	}

	return Mesh_Create(vertices[:], indices[:])
}

// Creates a square-based pyramid centered around the origin.
Mesh_Create_Pyramid :: proc() -> (Mesh, bool) {
	ny := f32(0.4472136)
	nz := f32(0.8944272)
	nx := f32(0.8944272)

	vertices := [18]Vertex{
		// Base
		{{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 0}},
		{{+0.5, -0.5, +0.5}, {0, -1, 0}, {1, 1}},
		{{+0.5, -0.5, -0.5}, {0, -1, 0}, {1, 0}},
		{{-0.5, -0.5, -0.5}, {0, -1, 0}, {0, 0}},
		{{-0.5, -0.5, +0.5}, {0, -1, 0}, {0, 1}},
		{{+0.5, -0.5, +0.5}, {0, -1, 0}, {1, 1}},

		// Sides
		{{-0.5, -0.5, +0.5}, {0, ny, nz}, {0, 0}},
		{{+0.5, -0.5, +0.5}, {0, ny, nz}, {1, 0}},
		{{ 0.0, +0.5,  0.0}, {0, ny, nz}, {0.5, 1}},

		{{+0.5, -0.5, +0.5}, {nx, ny, 0}, {0, 0}},
		{{+0.5, -0.5, -0.5}, {nx, ny, 0}, {1, 0}},
		{{ 0.0, +0.5,  0.0}, {nx, ny, 0}, {0.5, 1}},

		{{+0.5, -0.5, -0.5}, {0, ny, -nz}, {0, 0}},
		{{-0.5, -0.5, -0.5}, {0, ny, -nz}, {1, 0}},
		{{ 0.0, +0.5,  0.0}, {0, ny, -nz}, {0.5, 1}},

		{{-0.5, -0.5, -0.5}, {-nx, ny, 0}, {0, 0}},
		{{-0.5, -0.5, +0.5}, {-nx, ny, 0}, {1, 0}},
		{{ 0.0, +0.5,  0.0}, {-nx, ny, 0}, {0.5, 1}},
	}

	return Mesh_Create(vertices[:])
}

// Creates a cone centered around the origin with its base at y=-0.5.
Mesh_Create_Cone :: proc(segments: int = 32) -> (Mesh, bool) {
	segCount := segments
	if segCount < 3 do segCount = 3

	vertices := make([dynamic]Vertex, 0, segCount * 6, context.temp_allocator)
	radius := f32(0.5)
	height := f32(1.0)
	apex := eng.Vec3{0, 0.5, 0}
	center := eng.Vec3{0, -0.5, 0}

	for i in 0 ..< segCount {
		a0 := f32(i) / f32(segCount) * f32(2.0 * math.PI)
		a1 := f32(i + 1) / f32(segCount) * f32(2.0 * math.PI)
		c0 := math.cos(a0)
		s0 := math.sin(a0)
		c1 := math.cos(a1)
		s1 := math.sin(a1)

		p0 := eng.Vec3{c0 * radius, -0.5, s0 * radius}
		p1 := eng.Vec3{c1 * radius, -0.5, s1 * radius}
		n0 := eng.Vec3_Normalize(eng.Vec3{c0, radius / height, s0})
		n1 := eng.Vec3_Normalize(eng.Vec3{c1, radius / height, s1})
		na := eng.Vec3_Normalize(n0 + n1)

		append(&vertices, Vertex{apex, na, {0.5, 1}})
		append(&vertices, Vertex{p1, n1, {1, 0}})
		append(&vertices, Vertex{p0, n0, {0, 0}})

		append(&vertices, Vertex{center, {0, -1, 0}, {0.5, 0.5}})
		append(&vertices, Vertex{p0, {0, -1, 0}, {0, 0}})
		append(&vertices, Vertex{p1, {0, -1, 0}, {1, 0}})
	}

	return Mesh_Create(vertices[:])
}

// Creates an XZ plane centered at the origin.
Mesh_Create_Plane :: proc(
	width:         f32 = 1,
	depth:         f32 = 1,
	subdivisionsX: int = 1,
	subdivisionsZ: int = 1,
) -> (Mesh, bool) {
	cols := subdivisionsX + 1
	rows := subdivisionsZ + 1

	verts   := make([dynamic]Vertex, 0, cols * rows,                    context.temp_allocator)
	indices := make([dynamic]u32,    0, subdivisionsX * subdivisionsZ * 6, context.temp_allocator)

	halfW := width * 0.5
	halfD := depth * 0.5

	for z in 0..<rows {
		for x in 0..<cols {
			fx := f32(x) / f32(subdivisionsX)
			fz := f32(z) / f32(subdivisionsZ)
			append(&verts, Vertex{
				pos    = {fx * width - halfW, 0, fz * depth - halfD},
				normal = {0, 1, 0},
				uv     = {fx, fz},
			})
		}
	}

	for z in 0..<subdivisionsZ {
		for x in 0..<subdivisionsX {
			tl := u32(z * cols + x)
			tr := tl + 1
			bl := tl + u32(cols)
			br := bl + 1
			append(&indices, tl, bl, tr)
			append(&indices, tr, bl, br)
		}
	}

	return Mesh_Create(verts[:], indices[:])
}

// Creates a quad on the XY plane centered at the origin.
Mesh_Create_Quad :: proc(width: f32 = 1, height: f32 = 1) -> (Mesh, bool) {
	hw := width  * 0.5
	hh := height * 0.5
	vertices := [4]Vertex{
		{{-hw, -hh, 0}, {0, 0, 1}, {0, 0}},
		{{ hw, -hh, 0}, {0, 0, 1}, {1, 0}},
		{{ hw,  hh, 0}, {0, 0, 1}, {1, 1}},
		{{-hw,  hh, 0}, {0, 0, 1}, {0, 1}},
	}
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	return Mesh_Create(vertices[:], indices[:])
}
