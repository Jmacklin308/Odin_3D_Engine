package renderer

import gl "vendor:OpenGL"
import "core:fmt"
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
	indexCount:  i32,
	vertexCount: i32,
	indexed:     bool,
}

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

Mesh_Destroy :: proc(mesh: ^Mesh) {
	if mesh.ebo != 0 do gl.DeleteBuffers(1, &mesh.ebo)
	if mesh.vbo != 0 do gl.DeleteBuffers(1, &mesh.vbo)
	if mesh.vao != 0 do gl.DeleteVertexArrays(1, &mesh.vao)
	mesh^ = {}
}

Mesh_Draw :: proc(mesh: ^Mesh) {
	gl.BindVertexArray(mesh.vao)
	if mesh.indexed {
		gl.DrawElements(gl.TRIANGLES, mesh.indexCount, gl.UNSIGNED_INT, nil)
	} else {
		gl.DrawArrays(gl.TRIANGLES, 0, mesh.vertexCount)
	}
	gl.BindVertexArray(0)
}

// =============================================================================
// Primitive Generators
// =============================================================================

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
