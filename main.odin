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
	// Cursor starts unlocked — right-click to enter fly mode (Unity/Godot style).

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

	selection := new(scene.Selection_Set)
	defer free(selection)

	marquee: scene.Marquee_Selection

	for eng.Running() {
		eng.Begin_Frame()

		fps := eng.Get_FPS()
		title := fmt.ctprintf(
			"3D Engine | %d entities | %d selected | FPS: %.0f | %.2f ms | [RMB] fly  [LMB] select  [Shift+LMB] add",
			world.count, selection.count, fps, 1000.0 / fps,
		)

		eng.Window_Set_Title(eng.Get_Window(), title)
		dt  := eng.Get_Delta_Time()
		inp := eng.Get_Input()
		win := eng.Get_Window()

		if eng.Input_Key_Pressed(inp, eng.KEY_ESCAPE) do eng.Quit()

		// Right-click fly mode (Unity/Godot style).
		eng.Camera_FPS_Update_RMB(&cam, inp, win, dt)

		screenSize := eng.Vec2{f32(win.width), f32(win.height)}
		additiveSelection := eng.Input_Key_Down(inp, eng.KEY_LEFT_SHIFT)

		// Left mouse supports both click-pick and drag marquee while the cursor is free.
		if !inp.cursorLocked {
			if eng.Input_Mouse_Pressed(inp, eng.MOUSE_LEFT) {
				scene.Marquee_Begin(&marquee, inp.mousePos)
			}

			if marquee.active && eng.Input_Mouse_Down(inp, eng.MOUSE_LEFT) {
				scene.Marquee_Update(&marquee, inp.mousePos)
			}

			if marquee.active && eng.Input_Mouse_Released(inp, eng.MOUSE_LEFT) {
				if marquee.dragging {
					if !additiveSelection do scene.Selection_Clear(selection)
					scene.Scene_Select_Marquee(world, selection, &marquee, screenSize, &cam, win.aspect)
				} else {
					origin, dir := scene.Scene_Ray_From_Screen(inp.mousePos, screenSize, &cam, win.aspect)
					picked := scene.Scene_Pick(world, origin, dir)

					if picked != scene.ENTITY_NULL {
						if additiveSelection {
							scene.Selection_Add_ID(selection, world, picked)
						} else {
							scene.Selection_Set_Single(selection, world, picked)
						}
					} else if !additiveSelection {
						scene.Selection_Clear(selection)
					}
				}

				scene.Marquee_End(&marquee)
			}
		}

		rend.Renderer_Begin(&r, &cam, win.aspect)

		// Draw all ECS entities — selected one is tinted yellow.
		scene.Scene_Render_System(world, selection)

		rend.Renderer_Draw_Grid(&r)
		if marquee.dragging {
			rend.Renderer_Draw_Marquee(&r, screenSize, marquee.start, marquee.current)
		}

		rend.Renderer_End(&r)
		eng.End_Frame()
	}
}
