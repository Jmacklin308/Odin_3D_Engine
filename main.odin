package main

import eng "engine"
import rend "renderer"
import scene "scene"
import "core:fmt"
import "core:mem"

// Package-level pointer so _mesh_resolver can reference it without a closure.
@(private)
_cube_mesh: ^rend.Mesh

@(private)
_mesh_resolver :: proc(name: string) -> (^rend.Mesh, bool) {
	switch name {
	case "cube": return _cube_mesh, _cube_mesh != nil
	}
	return nil, false
}

main :: proc() {
	// for debugging!
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
	// load our config
	cfg := eng.DEFAULT_CONFIG
	cfg.debug.showGrid = true

	if !eng.Init(cfg) do return
	defer eng.Shutdown()
	eng.Window_Set_Title(eng.Get_Window(), "Odin 3D Engine")

	r: rend.Renderer
	if !rend.Renderer_Init(&r) {
		fmt.eprintln("Failed to init renderer.")
		return
	}
	defer rend.Renderer_Shutdown(&r)
	

	gizmo: scene.Transform_Gizmo
	if !scene.Transform_Gizmo_Init(&gizmo) {
		fmt.eprintln("Failed to init transform gizmo.")
		return
	}
	defer scene.Transform_Gizmo_Shutdown(&gizmo)

	cam := eng.Camera_Create({0, 80, 300}, 75)
	eng.Camera_Look_At(&cam, {0, 0, 0})
	focusAnim:           eng.Camera_Focus_State
	focusDoubleTapTimer: f32 // counts down from FOCUS_DOUBLE_TAP_WINDOW after first F press
	// Cursor starts unlocked - right-click to enter fly mode.

	cube, cubeOk := rend.Mesh_Create_Cube()
	if !cubeOk {
		fmt.eprintln("Failed to create cube mesh.")
		return
	}
	defer rend.Mesh_Destroy(&cube)
	_cube_mesh = &cube

	// --- Scene / ECS setup ---
	// World is ~10 MB; allocate on the heap to avoid stack overflow.
	world := new(scene.World)
	scene.World_Init(world, &r)
	defer {
		scene.World_Shutdown(world)
		free(world)
	}

	cubeKey, keyOk := scene.World_Register_Mesh(world, &cube, "cube")
	if !keyOk {
		fmt.eprintln("Failed to register cube mesh with scene.")
		return
	}

	// Spawn a grid of cubes.
	GRID :: 100
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

	history: scene.Undo_History
	defer scene.Undo_History_Destroy(&history)

	clipboard: scene.Clipboard

	marquee: scene.Marquee_Selection

	for eng.Running() {
		eng.Begin_Frame()

		fps := eng.Get_FPS()
		dt  := eng.Get_Delta_Time()
		inp := eng.Get_Input()
		win := eng.Get_Window()

		if eng.Input_Key_Pressed(inp, eng.KEY_ESCAPE) do eng.Quit()

		if !scene.Transform_Gizmo_Is_Dragging(&gizmo) {
			eng.Camera_FPS_Update_RMB(&cam, inp, win, dt)
		} else if inp.cursorLocked {
			eng.Input_Set_Cursor_Locked(inp, win, false)
		}

		// Cancel focus animation when the user enters fly mode.
		if inp.cursorLocked {
			eng.Camera_Focus_Cancel(&focusAnim)
		}
		eng.Camera_Focus_Update(&focusAnim, &cam, dt)

		screenSize := eng.Vec2{f32(win.width), f32(win.height)}
		additiveSelection := eng.Input_Key_Down(inp, eng.KEY_LEFT_SHIFT)

		if !inp.cursorLocked {
			if eng.Input_Key_Pressed(inp, eng.KEY_W) do scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_TRANSLATE)
			if eng.Input_Key_Pressed(inp, eng.KEY_E) do scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_ROTATE)
			if eng.Input_Key_Pressed(inp, eng.KEY_R) do scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_SCALE)

			FOCUS_DOUBLE_TAP_WINDOW :: f32(0.25)
			if eng.Input_Key_Pressed(inp, eng.KEY_F) {
				focusCenter, focusRadius, focusOk := scene.Selection_Get_Focus_Bounds(world, selection)
				if focusOk {
					if focusDoubleTapTimer > 0 {
						// Second tap within the window — fly in close.
						eng.Camera_Focus_Begin_Close(&focusAnim, &cam, focusCenter, focusRadius)
						focusDoubleTapTimer = 0
					} else {
						// First tap — normal framing focus.
						eng.Camera_Focus_Begin(&focusAnim, &cam, focusCenter, focusRadius)
						focusDoubleTapTimer = FOCUS_DOUBLE_TAP_WINDOW
					}
				}
			}
			focusDoubleTapTimer -= dt
			if focusDoubleTapTimer < 0 do focusDoubleTapTimer = 0

			ctrlDown := eng.Input_Key_Down(inp, eng.KEY_LEFT_CONTROL)
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_S) {
				scene.Scene_Save(world, "scene.o3ds")
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_O) {
				scene.Scene_Load(world, "scene.o3ds", _mesh_resolver)
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_Z) {
				scene.Undo_Apply(&history, world, selection)
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_Y) {
				scene.Undo_Redo(&history, world, selection)
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_C) {
				scene.Clipboard_Copy(world, selection, &clipboard)
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_V) {
				pasteOrigin, pasteDir := scene.Scene_Ray_From_Screen(inp.mousePos, screenSize, &cam, win.aspect)
				if ids, snap, ok := scene.Clipboard_Paste(world, selection, &clipboard, pasteOrigin, pasteDir); ok {
					scene.Undo_Paste_Commit(&history, ids, snap)
				}
			}
		}

		if !inp.cursorLocked {
			gizmoCaptured, gizmoCommitted := scene.Transform_Gizmo_Handle_Input(&gizmo, world, selection, inp, &cam, screenSize, win.aspect)
			if gizmoCommitted {
				scene.Undo_Gizmo_Commit(&history, &gizmo, world)
			}

			if !gizmoCaptured {
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
		}

		rend.Renderer_Begin(&r, &cam, win.aspect)
		scene.Scene_Render_System(world, selection)
		scene.Transform_Gizmo_Draw(&gizmo, &r, world, selection, &cam, screenSize)
		rend.Renderer_Draw_Grid(&r)
		if marquee.dragging {
			rend.Renderer_Draw_Marquee(&r, screenSize, marquee.start, marquee.current)
		}
		hudText := fmt.tprintf(
			"ODIN 3D ENGINE\nENTITIES %d\nSELECTED %d\nFPS %.0f\nTOOL %s\nW MOVE  E ROTATE  R SCALE\nF FOCUS\nRMB FLY\nLMB SELECT DRAG\nSHIFT LMB ADD\nCTRL+Z UNDO  CTRL+Y REDO\nCTRL+C COPY  CTRL+V PASTE",
			world.count, selection.count, fps, scene.Transform_Gizmo_Mode_Label(scene.Transform_Gizmo_Get_Mode(&gizmo)),
		)
		hudPos := eng.Vec2{14, 14}
		hudPad := eng.Vec2{8, 8}
		hudSize := rend.Renderer_Measure_Debug_Text(hudText, 2.0)
		rend.Renderer_Draw_Screen_Rect(&r, screenSize, hudPos - hudPad, hudPos + hudSize + hudPad, {0.03, 0.04, 0.06, 0.78})
		rend.Renderer_Draw_Debug_Text(&r, screenSize, hudPos, hudText, 2.0, {0.95, 0.97, 1.0, 1.0})
		rend.Renderer_End(&r)

		eng.End_Frame()
	}
}
