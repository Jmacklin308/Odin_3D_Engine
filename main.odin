package main

import eng "engine"
import rend "renderer"
import scene "scene"
import "core:fmt"
import "core:mem"




main :: proc() {
	//for debugging!
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
// ------------------- Rest of Program ------------------- 
	//load our config
	cfg := eng.DEFAULT_CONFIG
	cfg.debug.showGrid = true
	
	if !eng.Init(cfg) do return
	defer eng.Shutdown()

	r: rend.Renderer
	if !rend.Renderer_Init(&r) {
		fmt.eprintln("Failed to init renderer.")
		return
	}
	defer rend.Renderer_Shutdown(&r)

	cam := eng.Camera_Create({0, 80, 300}, 75)
	eng.Camera_Look_At(&cam, {0, 0, 0})
	eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), true)

	cube, cubeOk := rend.Mesh_Create_Cube()
	if !cubeOk {
		fmt.eprintln("Failed to create cube mesh.")
		return
	}
	defer rend.Mesh_Destroy(&cube)

	// --- Scene / ECS setup ---
	// World is ~10 MB; allocate on the heap to avoid stack overflow.
	world := new(scene.World)
	scene.World_Init(world, &r)
	defer {
		scene.World_Shutdown(world)
		free(world)
	}

	cubeKey, keyOk := scene.World_Register_Mesh(world, &cube)
	if !keyOk {
		fmt.eprintln("Failed to register cube mesh with scene.")
		return
	}

	// Spawn a 100×100 grid of cubes (10,000 entities).
	// Each entity gets a Transform and a MeshRef.
	GRID :: 40
	SPACING :: 1.5
	for row in 0 ..< GRID {
		for col in 0 ..< GRID {
			e := scene.World_Entity_Create(world)
			x := (f32(col) - f32(GRID) * 0.5) * SPACING
			z := (f32(row) - f32(GRID) * 0.5) * SPACING
			scene.World_Add_Transform(world, e, eng.Transform{
				position = {x, 0, z},
				rotation = eng.QUAT_IDENTITY,
				scale    = {0.4, 0.4, 0.4},
			})
			scene.World_Add_MeshRef(world, e, scene.MeshRef{
				meshKey = cubeKey,
				color   = {0.8, 0.4, 0.2},
			})
		}
	}

	for eng.Running() {
		eng.Begin_Frame()

		fps := eng.Get_FPS()
		title := fmt.ctprintf(
			"3D Engine | %d entities | FPS: %.0f | %.2f ms",
			world.count, fps, 1000.0 / fps,
		)
		eng.Window_Set_Title(eng.Get_Window(), title)

		dt  := eng.Get_Delta_Time()
		inp := eng.Get_Input()
		win := eng.Get_Window()

		if eng.Input_Key_Pressed(inp, eng.KEY_ESCAPE) do eng.Quit()

		if eng.Input_Key_Pressed(inp, eng.KEY_TAB) {
			eng.Input_Set_Cursor_Locked(inp, win, !inp.cursorLocked)
		}

		eng.Camera_FPS_Update(&cam, inp, dt)

		rend.Renderer_Begin(&r, &cam, win.aspect)

		// Draw all ECS entities — one instanced draw call for the whole grid.
		scene.Scene_Render_System(world)

		rend.Renderer_Draw_Grid(&r)

		rend.Renderer_End(&r)
		eng.End_Frame()
	}
}
