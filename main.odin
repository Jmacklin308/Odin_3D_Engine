package main

import eng "engine"
import rend "renderer"
import scene "scene"
import "core:fmt"
import "core:math"
import "core:mem"

// Package-level pointer so _mesh_resolver can reference it without a closure.
@(private)
_cube_mesh: ^rend.Mesh
@(private)
_pyramid_mesh: ^rend.Mesh
@(private)
_cone_mesh: ^rend.Mesh

@(private)
_mesh_resolver :: proc(name: string) -> (^rend.Mesh, bool) {
	switch name {
	case "cube": return _cube_mesh, _cube_mesh != nil
	case "pyramid": return _pyramid_mesh, _pyramid_mesh != nil
	case "cone": return _cone_mesh, _cone_mesh != nil
	}
	return nil, false
}

Placement_Kind :: distinct int

PLACEMENT_NONE :: Placement_Kind(0)
PLACEMENT_CUBE :: Placement_Kind(1)
PLACEMENT_PYRAMID :: Placement_Kind(2)
PLACEMENT_CONE :: Placement_Kind(3)

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
	editorSettings, settingsLoaded := Editor_Settings_Load()

	// load our config
	cfg := eng.DEFAULT_CONFIG
	Editor_Settings_Apply_Config(&editorSettings, &cfg)

	if !eng.Init(cfg) do return
	defer eng.Shutdown()
	eng.Window_Set_Title(eng.Get_Window(), "Odin 3D Engine")

	r: rend.Renderer
	if !rend.Renderer_Init(&r) {
		fmt.eprintln("Failed to init renderer.")
		return
	}
	defer rend.Renderer_Shutdown(&r)
	rend.Renderer_Set_Clear_Color(&r, Editor_Settings_Clear_Color(&editorSettings))

	ui: rend.UI_Context
	rend.UI_Init(&ui)
	defer rend.UI_Shutdown(&ui)

	notifications: rend.Notification_Tray
	rend.Notification_Tray_Init(&notifications)
	defer rend.Notification_Tray_Shutdown(&notifications)
	if settingsLoaded {
		rend.Notification_Tray_Push(&notifications, "EDITOR ONLINE - SETTINGS LOADED", .SUCCESS, 2.8)
	} else {
		rend.Notification_Tray_Push(&notifications, "EDITOR ONLINE", .SUCCESS, 2.8)
	}

	gizmo: scene.Transform_Gizmo
	if !scene.Transform_Gizmo_Init(&gizmo) {
		fmt.eprintln("Failed to init transform gizmo.")
		return
	}
	defer scene.Transform_Gizmo_Shutdown(&gizmo)

	cam := eng.Camera_Create({0, 80, 300}, 75)
	eng.Camera_Look_At(&cam, {0, 0, 0})
	focusAnim:           eng.Camera_Focus_State
	orbitZoom:           eng.CameraOrbitZoomState
	focusDoubleTapTimer: f32 // counts down from FOCUS_DOUBLE_TAP_WINDOW after first F press
	// Cursor starts unlocked - right-click to enter fly mode.

	cube, cubeOk := rend.Mesh_Create_Cube()
	if !cubeOk {
		fmt.eprintln("Failed to create cube mesh.")
		return
	}
	defer rend.Mesh_Destroy(&cube)
	_cube_mesh = &cube

	pyramid, pyramidOk := rend.Mesh_Create_Pyramid()
	if !pyramidOk {
		fmt.eprintln("Failed to create pyramid mesh.")
		return
	}
	defer rend.Mesh_Destroy(&pyramid)
	_pyramid_mesh = &pyramid

	cone, coneOk := rend.Mesh_Create_Cone()
	if !coneOk {
		fmt.eprintln("Failed to create cone mesh.")
		return
	}
	defer rend.Mesh_Destroy(&cone)
	_cone_mesh = &cone

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
	pyramidKey, pyramidKeyOk := scene.World_Register_Mesh(world, &pyramid, "pyramid")
	if !pyramidKeyOk {
		fmt.eprintln("Failed to register pyramid mesh with scene.")
		return
	}
	coneKey, coneKeyOk := scene.World_Register_Mesh(world, &cone, "cone")
	if !coneKeyOk {
		fmt.eprintln("Failed to register cone mesh with scene.")
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
	defer scene.Clipboard_Destroy(&clipboard)

	marquee: scene.Marquee_Selection
	placementKind := PLACEMENT_NONE
	placeDrawerOpen := false
	placeDrawerT: f32
	settingsOpen := false

	for eng.Running() {
		eng.Begin_Frame()

		fps := eng.Get_FPS()
		dt  := eng.Get_Delta_Time()
		inp := eng.Get_Input()
		win := eng.Get_Window()
		altDown := eng.Input_Key_Down(inp, eng.KEY_LEFT_ALT) || eng.Input_Key_Down(inp, eng.KEY_RIGHT_ALT)
		altPressed := eng.Input_Key_Pressed(inp, eng.KEY_LEFT_ALT) || eng.Input_Key_Pressed(inp, eng.KEY_RIGHT_ALT)
		shiftDown := eng.Input_Key_Down(inp, eng.KEY_LEFT_SHIFT)

		if eng.Input_Key_Pressed(inp, eng.KEY_ESCAPE) {
			if settingsOpen {
				settingsOpen = false
			} else if placementKind != PLACEMENT_NONE {
				placementKind = PLACEMENT_NONE
				rend.Notification_Tray_Push(&notifications, "PLACEMENT CANCELLED", .WARNING)
			} else {
				eng.Quit()
			}
		}

		if !inp.cursorLocked && eng.Input_Key_Pressed(inp, eng.KEY_F10) {
			settingsOpen = !settingsOpen
		}

		if !scene.Transform_Gizmo_Is_Dragging(&gizmo) {
			orbitCenter, orbitRadius, orbitOk := scene.Selection_Get_Focus_Bounds(world, selection)
			rmbDown := eng.Input_Mouse_Down(inp, eng.MOUSE_RIGHT)
			scrollY := f32(0)
			if altDown do scrollY = eng.Input_Scroll_Delta(inp).y
			zoomRequested := orbitOk && altDown && scrollY != 0
			orbiting := orbitOk && altDown && rmbDown

			if orbiting {
				eng.Camera_Orbit_Update_RMB(&cam, inp, win, orbitCenter, altPressed, Editor_Settings_Camera_Params(&editorSettings))
				if !zoomRequested do eng.Camera_Orbit_Zoom_Cancel(&orbitZoom)
			} else {
				eng.Camera_FPS_Update_RMB(&cam, inp, win, dt, Editor_Settings_Camera_Params(&editorSettings))
				if rmbDown do eng.Camera_Orbit_Zoom_Cancel(&orbitZoom)
			}

			if zoomRequested || (!rmbDown && orbitOk && orbitZoom.active) {
				eng.Camera_Orbit_Zoom_Update(&orbitZoom, &cam, orbitCenter, orbitRadius, scrollY, dt, shiftDown)
			} else if !orbitOk || rmbDown {
				eng.Camera_Orbit_Zoom_Cancel(&orbitZoom)
			}
		} else if inp.cursorLocked {
			eng.Input_Set_Cursor_Locked(inp, win, false)
			eng.Camera_Orbit_Zoom_Cancel(&orbitZoom)
		}

		// Cancel focus animation when the user enters fly mode.
		if inp.cursorLocked || orbitZoom.active {
			eng.Camera_Focus_Cancel(&focusAnim)
		}
		eng.Camera_Focus_Update(&focusAnim, &cam, dt)

		screenSize := eng.Vec2{f32(win.width), f32(win.height)}
		uiScreenSize := screenSize / clamp(editorSettings.editorScale, 0.75, 1.75)
		additiveSelection := shiftDown
		currentMode := scene.Transform_Gizmo_Get_Mode(&gizmo)
		drawerTarget := f32(1.0) if placeDrawerOpen else f32(0.0)
		drawerEase := 1.0 - math.pow(f32(0.5), dt * 10.0)
		placeDrawerT = eng.F32_Lerp(placeDrawerT, drawerTarget, clamp(drawerEase, 0, 1))

		rend.UI_Begin(&ui, &r, screenSize, inp, dt, editorSettings.editorScale)
		uiScreenSize = rend.UI_Layout_Screen_Size(&ui)
		rend.UI_Panel(&ui, {14, 14, 292, 250})
		rend.UI_Label(&ui, {30, 30}, "ODIN 3D ENGINE", 2.0)
		rend.UI_Label(&ui, {30, 54}, fmt.tprintf("ENTITIES %d  SELECTED %d", world.count, selection.count), 1.5, ui.theme.textMuted)
		rend.UI_Label(&ui, {30, 73}, fmt.tprintf("FPS %.0f", fps), 1.5, ui.theme.textMuted)

		if rend.UI_Button(&ui, "tool_translate", {30, 100, 80, 32}, "MOVE", currentMode == scene.GIZMO_MODE_TRANSLATE) {
			placementKind = PLACEMENT_NONE
			scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_TRANSLATE)
			rend.Notification_Tray_Push(&notifications, "MOVE TOOL READY", .INFO)
		}
		if rend.UI_Button(&ui, "tool_rotate", {120, 100, 80, 32}, "ROTATE", currentMode == scene.GIZMO_MODE_ROTATE) {
			placementKind = PLACEMENT_NONE
			scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_ROTATE)
			rend.Notification_Tray_Push(&notifications, "ROTATE TOOL READY", .INFO)
		}
		if rend.UI_Button(&ui, "tool_scale", {210, 100, 80, 32}, "SCALE", currentMode == scene.GIZMO_MODE_SCALE) {
			placementKind = PLACEMENT_NONE
			scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_SCALE)
			rend.Notification_Tray_Push(&notifications, "SCALE TOOL READY", .INFO)
		}

		rend.UI_Label(&ui, {30, 148}, "W/E/R TOOLS   F FOCUS", 1.5, ui.theme.textMuted)
		rend.UI_Label(&ui, {30, 167}, "RMB FLY   LMB SELECT/DRAG", 1.5, ui.theme.textMuted)
		rend.UI_Label(&ui, {30, 186}, "SHIFT ADD   CTRL+Z/Y UNDO", 1.5, ui.theme.textMuted)
		rend.UI_Label(&ui, {30, 205}, "CTRL+S/O SAVE/LOAD", 1.5, ui.theme.textMuted)
		if rend.UI_Button(&ui, "settings_open", {30, 224, 116, 28}, "SETTINGS", settingsOpen) {
			settingsOpen = !settingsOpen
		}
		rend.UI_Label(&ui, {158, 230}, "F10", 1.35, ui.theme.textMuted)

		drawerW := f32(560.0)
		drawerH := f32(120.0)
		drawerX := (uiScreenSize.x - drawerW) * 0.5
		drawerClosedY := uiScreenSize.y - 18.0
		drawerOpenY := uiScreenSize.y - drawerH
		drawerY := eng.F32_Lerp(drawerClosedY, drawerOpenY, placeDrawerT)
		arrowText := "^" if !placeDrawerOpen else "V"

		if rend.UI_Button(&ui, "place_drawer_toggle", {drawerX + drawerW * 0.5 - 22, drawerY - 24, 44, 24}, arrowText) {
			placeDrawerOpen = !placeDrawerOpen
		}
		rend.UI_Panel(&ui, {drawerX, drawerY, drawerW, drawerH})

		if placeDrawerT > 0.08 {
			rend.UI_Label(&ui, {drawerX + 18, drawerY + 17}, "PLACE", 1.5, ui.theme.textMuted)
			cubeSelected := placementKind == PLACEMENT_CUBE
			if rend.UI_Button(&ui, "place_cube", {drawerX + 18, drawerY + 40, 82, 62}, "", cubeSelected) {
				placementKind = PLACEMENT_CUBE
				rend.Notification_Tray_Push(&notifications, "CUBE GHOST LOADED", .PLACE)
			}
			cubeHover := rend.UI_Hover_Amount(&ui, "place_cube")
			cubeAngle := rend.UI_Time(&ui) * (0.65 + cubeHover * 3.0)
			rend.UI_Model_Preview(&ui, {drawerX + 33, drawerY + 43, 52, 38}, &cube, cubeAngle, {0.8, 0.4, 0.2})
			rend.UI_Label(&ui, {drawerX + 39, drawerY + 86}, "CUBE", 1.25, ui.theme.text)

			pyramidSelected := placementKind == PLACEMENT_PYRAMID
			if rend.UI_Button(&ui, "place_pyramid", {drawerX + 108, drawerY + 40, 82, 62}, "", pyramidSelected) {
				placementKind = PLACEMENT_PYRAMID
				rend.Notification_Tray_Push(&notifications, "PYRAMID GHOST LOADED", .PLACE)
			}
			pyramidHover := rend.UI_Hover_Amount(&ui, "place_pyramid")
			pyramidAngle := rend.UI_Time(&ui) * (0.65 + pyramidHover * 3.0)
			rend.UI_Model_Preview(&ui, {drawerX + 123, drawerY + 43, 52, 38}, &pyramid, pyramidAngle, {0.95, 0.68, 0.22})
			rend.UI_Label(&ui, {drawerX + 115, drawerY + 86}, "PYRAMID", 1.25, ui.theme.text)

			coneSelected := placementKind == PLACEMENT_CONE
			if rend.UI_Button(&ui, "place_cone", {drawerX + 198, drawerY + 40, 82, 62}, "", coneSelected) {
				placementKind = PLACEMENT_CONE
				rend.Notification_Tray_Push(&notifications, "CONE GHOST LOADED", .PLACE)
			}
			coneHover := rend.UI_Hover_Amount(&ui, "place_cone")
			coneAngle := rend.UI_Time(&ui) * (0.65 + coneHover * 3.0)
			rend.UI_Model_Preview(&ui, {drawerX + 213, drawerY + 43, 52, 38}, &cone, coneAngle, {0.35, 0.75, 0.95})
			rend.UI_Label(&ui, {drawerX + 220, drawerY + 86}, "CONE", 1.25, ui.theme.text)

			if placementKind != PLACEMENT_NONE {
				rend.UI_Label(&ui, {drawerX + 312, drawerY + 52}, "CLICK SCENE TO PLACE", 1.5, ui.theme.text)
				rend.UI_Label(&ui, {drawerX + 312, drawerY + 72}, "ESC CANCELS PLACEMENT", 1.5, ui.theme.textMuted)
			}
		}
		if settingsOpen {
			Editor_Settings_Draw_Menu(&ui, &editorSettings, &notifications, &r, win, uiScreenSize)
		}
		rend.UI_End(&ui)

		uiCaptured := rend.UI_Wants_Mouse(&ui)

		if !inp.cursorLocked {
			if eng.Input_Key_Pressed(inp, eng.KEY_W) {
				placementKind = PLACEMENT_NONE
				scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_TRANSLATE)
				rend.Notification_Tray_Push(&notifications, "MOVE TOOL READY", .INFO)
			}
			if eng.Input_Key_Pressed(inp, eng.KEY_E) {
				placementKind = PLACEMENT_NONE
				scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_ROTATE)
				rend.Notification_Tray_Push(&notifications, "ROTATE TOOL READY", .INFO)
			}
			if eng.Input_Key_Pressed(inp, eng.KEY_R) {
				placementKind = PLACEMENT_NONE
				scene.Transform_Gizmo_Set_Mode(&gizmo, scene.GIZMO_MODE_SCALE)
				rend.Notification_Tray_Push(&notifications, "SCALE TOOL READY", .INFO)
			}

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
				if scene.Scene_Save(world, "scene.o3ds") {
					rend.Notification_Tray_Push(&notifications, "SCENE SAVED", .SUCCESS)
				} else {
					rend.Notification_Tray_Push(&notifications, "SAVE FAILED", .ERROR, 3.0)
				}
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_O) {
				if scene.Scene_Load(world, "scene.o3ds", _mesh_resolver) {
					rend.Notification_Tray_Push(&notifications, "SCENE LOADED", .SUCCESS)
				} else {
					rend.Notification_Tray_Push(&notifications, "LOAD FAILED", .ERROR, 3.0)
				}
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_Z) {
				if scene.Undo_Apply(&history, world, selection) {
					rend.Notification_Tray_Push(&notifications, "UNDONE PROP", .UNDO)
				} else {
					rend.Notification_Tray_Push(&notifications, "NOTHING TO UNDO", .WARNING)
				}
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_Y) {
				if scene.Undo_Redo(&history, world, selection) {
					rend.Notification_Tray_Push(&notifications, "REDONE PROP", .UNDO)
				} else {
					rend.Notification_Tray_Push(&notifications, "NOTHING TO REDO", .WARNING)
				}
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_C) {
				scene.Clipboard_Copy(world, selection, &clipboard)
				rend.Notification_Tray_Push(&notifications, "COPIED SELECTION", .SUCCESS)
			}
			if ctrlDown && eng.Input_Key_Pressed(inp, eng.KEY_V) {
				pasteOrigin, pasteDir := scene.Scene_Ray_From_Screen(inp.mousePos, screenSize, &cam, win.aspect)
				if ids, snap, ok := scene.Clipboard_Paste(world, selection, &clipboard, pasteOrigin, pasteDir); ok {
					scene.Undo_Paste_Commit(&history, ids, snap)
					rend.Notification_Tray_Push(&notifications, "PASTED SELECTION", .PLACE)
				} else {
					rend.Notification_Tray_Push(&notifications, "CLIPBOARD EMPTY", .WARNING)
				}
			}
		}

		if placementKind != PLACEMENT_NONE && !inp.cursorLocked && !uiCaptured && eng.Input_Mouse_Pressed(inp, eng.MOUSE_LEFT) {
			origin, dir := scene.Scene_Ray_From_Screen(inp.mousePos, screenSize, &cam, win.aspect)
			placePos := scene.Scene_Placement_Point_From_Ray(origin, dir)

			switch placementKind {
			case PLACEMENT_CUBE:
				e := scene.World_Entity_Create(world)
				scene.World_Add_Transform(world, e, eng.Transform{
					position = {placePos.x, 0.2, placePos.z},
					rotation = eng.QUAT_IDENTITY,
					scale    = {0.4, 0.4, 0.4},
				})
				scene.World_Add_MeshRef(world, e, scene.MeshRef{
					meshKey = cubeKey,
					color   = {0.8, 0.4, 0.2},
				})
				scene.Selection_Set_Single(selection, world, e)
				rend.Notification_Tray_Push(&notifications, "CUBE PLACED", .PLACE)
			case PLACEMENT_PYRAMID:
				e := scene.World_Entity_Create(world)
				scene.World_Add_Transform(world, e, eng.Transform{
					position = {placePos.x, 0.2, placePos.z},
					rotation = eng.QUAT_IDENTITY,
					scale    = {0.4, 0.4, 0.4},
				})
				scene.World_Add_MeshRef(world, e, scene.MeshRef{
					meshKey = pyramidKey,
					color   = {0.95, 0.68, 0.22},
				})
				scene.Selection_Set_Single(selection, world, e)
				rend.Notification_Tray_Push(&notifications, "PYRAMID PLACED", .PLACE)
			case PLACEMENT_CONE:
				e := scene.World_Entity_Create(world)
				scene.World_Add_Transform(world, e, eng.Transform{
					position = {placePos.x, 0.2, placePos.z},
					rotation = eng.QUAT_IDENTITY,
					scale    = {0.4, 0.4, 0.4},
				})
				scene.World_Add_MeshRef(world, e, scene.MeshRef{
					meshKey = coneKey,
					color   = {0.35, 0.75, 0.95},
				})
				scene.Selection_Set_Single(selection, world, e)
				rend.Notification_Tray_Push(&notifications, "CONE PLACED", .PLACE)
			}
		}

		if !inp.cursorLocked && !uiCaptured && placementKind == PLACEMENT_NONE {
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

		rend.Notification_Tray_Update(&notifications, dt)

		rend.Renderer_Begin(&r, &cam, win.aspect)
		scene.Scene_Render_System(world, selection)
		scene.Transform_Gizmo_Draw(&gizmo, &r, world, selection, &cam, screenSize)
		rend.Renderer_Draw_Grid(&r)
		if marquee.dragging {
			rend.Renderer_Draw_Marquee(&r, screenSize, marquee.start, marquee.current)
		}
		rend.UI_Render(&ui)
		rend.Notification_Tray_Render(&notifications, &r, screenSize, editorSettings.editorScale)
		rend.Renderer_End(&r)

		eng.End_Frame()
	}
}
