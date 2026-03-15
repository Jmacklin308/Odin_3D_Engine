package main

import eng "engine"
import rend "renderer"
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

	cam := eng.Camera_Create({0, 2, 5}, 75)
	eng.Camera_Look_At(&cam, {0, 0, 0})
	eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), true)

	cube, cubeOk := rend.Mesh_Create_Cube()
	if !cubeOk {
		fmt.eprintln("Failed to create cube mesh.")
		return
	}
	defer rend.Mesh_Destroy(&cube)

	// plane, planeOk := rend.Mesh_Create_Plane(20, 20, 10, 10)
	// if !planeOk {
	// 	fmt.eprintln("Failed to create plane mesh.")
	// 	return
	// }
	// defer rend.Mesh_Destroy(&plane)

	angle: f32 = 0

	for eng.Running() {
		eng.Begin_Frame()
		
		fps := eng.Get_FPS()
		title := fmt.ctprintf("3D Engine | FPS: %.0f | %.2f ms", fps, 1000.0 / fps)
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
			
		//rotate our cube
		angle += dt * 0.8
		cubeModel := eng.Mat4_Rotate(angle, {0.3, 1, 0.2})
		
		
		//draw our cube
		rend.Renderer_Draw_Mesh(&r, &cube, cubeModel, {0.8, 0.4, 0.2})

		planeModel := eng.Mat4_Translate({0, -0.5, 0})
		// rend.Renderer_Draw_Mesh(&r, &plane, planeModel, {0.3, 0.6, 0.3})

		// Draw our grid here
		rend.Renderer_Draw_Grid(&r)
		
		
		
		rend.Renderer_End(&r)
		eng.End_Frame()
	}
}
