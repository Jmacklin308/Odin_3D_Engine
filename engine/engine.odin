// Package engine — core systems: window, input, camera, math.
//
// Typical usage:
//
//     import eng "engine"
//     import rend "renderer"
//
//     main :: proc() {
//         ok := eng.Init()
//         if !ok do return
//         defer eng.Shutdown()
//
//         r: rend.Renderer
//         rend.Renderer_Init(&r)
//         defer rend.Renderer_Shutdown(&r)
//
//         cam := eng.Camera_Create({0, 5, 10}, 75)
//         eng.Camera_Look_At(&cam, {0, 0, 0})
//         eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), true)
//
//         for eng.Running() {
//             eng.Begin_Frame()
//             dt := eng.Get_Delta_Time()
//
//             eng.Camera_FPS_Update(&cam, eng.Get_Input(), dt)
//
//             rend.Renderer_Begin(&r, &cam, eng.Get_Window().aspect)
//             rend.Renderer_Draw_Mesh(&r, &myMesh, eng.MAT4_IDENTITY)
//             rend.Renderer_End(&r)
//
//             eng.End_Frame()
//         }
//     }
//
package engine

import "vendor:glfw"
import "core:fmt"

// =============================================================================
// Engine State
// =============================================================================

@(private)
_eng: _EngineState

@(private)
_EngineState :: struct {
	window:  Window,
	input:   Input,
	config:  EngineConfig,
	running: bool,

	// Timing
	deltaTime:     f32,
	lastFrameTime: f64,
	smoothFps:     f32,
}

// =============================================================================
// Lifecycle
// =============================================================================

// Initialise the engine. Call once before your game loop.
Init :: proc(cfg: EngineConfig = DEFAULT_CONFIG) -> bool {
	win, winOk := Window_Create(cfg.window)
	if !winOk do return false
	_eng.window = win
	_eng.config = cfg

	Input_Setup_Callbacks(&_eng.input, &_eng.window)

	_eng.lastFrameTime = glfw.GetTime()
	_eng.running       = true
	_eng.smoothFps     = 60

	fmt.println("[Engine] Initialised.")
	return true
}

// Shutdown the engine and free all resources.
Shutdown :: proc() {
	Window_Destroy(&_eng.window)
	fmt.println("[Engine] Shutdown complete.")
}

// Returns true while the window is open and no quit has been requested.
Running :: proc() -> bool {
	return _eng.running && !Window_Should_Close(&_eng.window)
}

// Request a clean shutdown at the end of the current frame.
Quit :: proc() {
	_eng.running = false
}

// =============================================================================
// Frame Management
// =============================================================================

Begin_Frame :: proc() {
	Input_Clear_Frame(&_eng.input)
	Window_Poll_Events()
	Input_Update(&_eng.input, &_eng.window)
	Window_Update_Size(&_eng.window)

	currentTime        := glfw.GetTime()
	_eng.deltaTime      = f32(currentTime - _eng.lastFrameTime)
	_eng.lastFrameTime  = currentTime

	MAX_DELTA :: f32(1.0 / 15.0)
	if _eng.deltaTime > MAX_DELTA {
		_eng.deltaTime = MAX_DELTA
	}

	if _eng.deltaTime > 0 {
		instantFps    := 1.0 / _eng.deltaTime
		_eng.smoothFps = _eng.smoothFps * 0.95 + instantFps * 0.05
	}
}

End_Frame :: proc() {
	Window_Swap_Buffers(&_eng.window)
}

// =============================================================================
// Accessors
// =============================================================================

Get_Window :: proc() -> ^Window {
	return &_eng.window
}

Get_Input :: proc() -> ^Input {
	return &_eng.input
}

Get_Delta_Time :: proc() -> f32 {
	return _eng.deltaTime
}

Get_FPS :: proc() -> f32 {
	return _eng.smoothFps
}

Get_Config :: proc() -> EngineConfig {
	return _eng.config
}
