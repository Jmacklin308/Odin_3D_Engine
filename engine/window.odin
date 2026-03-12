package engine

import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:fmt"

// =============================================================================
// Window Config
// =============================================================================

WindowConfig :: struct {
	title:    cstring,
	width:    i32,
	height:   i32,
	vsync:    bool,
	msaa:     i32, // MSAA samples: 0 = off, 4 = typical
	glMajor:  i32,
	glMinor:  i32,
	resizable: bool,
}

DEFAULT_WINDOW_CONFIG :: WindowConfig{
	title    = "3D Engine",
	width    = 1280,
	height   = 720,
	vsync    = true,
	msaa     = 4,
	glMajor  = 4,
	glMinor  = 1,
	resizable = true,
}

// =============================================================================
// Window
// =============================================================================

Window :: struct {
	handle:     glfw.WindowHandle,
	width:      i32,
	height:     i32,
	title:      cstring,
	// Aspect ratio cached here so you don't have to divide every frame.
	aspect:     f32,
}

// Initialise GLFW, create the window, and load OpenGL.
// Returns false and prints an error if anything goes wrong.
Window_Create :: proc(cfg: WindowConfig) -> (win: Window, ok: bool) {
	// GLFW init
	if !glfw.Init() {
		fmt.eprintln("[Window] Failed to initialise GLFW.")
		return {}, false
	}

	// OpenGL version hints
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, cfg.glMajor)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, cfg.glMinor)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE) // Required on macOS; harmless elsewhere

	if cfg.resizable {
		glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	} else {
		glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	}

	// Multisampling
	if cfg.msaa > 0 {
		glfw.WindowHint(glfw.SAMPLES, cfg.msaa)
	}

	win.handle = glfw.CreateWindow(cfg.width, cfg.height, cfg.title, nil, nil)
	if win.handle == nil {
		fmt.eprintln("[Window] Failed to create GLFW window.")
		glfw.Terminate()
		return {}, false
	}

	win.width  = cfg.width
	win.height = cfg.height
	win.title  = cfg.title
	win.aspect = f32(cfg.width) / f32(cfg.height)

	glfw.MakeContextCurrent(win.handle)

	// VSync: 1 = on, 0 = off. Turning it off will make your GPU cry.
	glfw.SwapInterval(cfg.vsync ? 1 : 0)

	// Load all OpenGL function pointers up to the requested version.
	gl.load_up_to(int(cfg.glMajor), int(cfg.glMinor), glfw.gl_set_proc_address)

	// Enable MSAA if requested
	if cfg.msaa > 0 {
		gl.Enable(gl.MULTISAMPLE)
	}

	// Depth testing — turned on here so meshes don't render inside-out.
	gl.Enable(gl.DEPTH_TEST)

	// Back-face culling — skip triangles facing away from the camera.
	// Doubles your draw performance for closed meshes. Leave it on.
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)

	return win, true
}

Window_Destroy :: proc(win: ^Window) {
	if win.handle != nil {
		glfw.DestroyWindow(win.handle)
		win.handle = nil
	}
	glfw.Terminate()
}

// Returns true while the window is open and the user hasn't pressed Alt+F4.
Window_Should_Close :: proc(win: ^Window) -> bool {
	return bool(glfw.WindowShouldClose(win.handle))
}

Window_Swap_Buffers :: proc(win: ^Window) {
	glfw.SwapBuffers(win.handle)
}

Window_Poll_Events :: proc() {
	glfw.PollEvents()
}

Window_Get_Size :: proc(win: ^Window) -> (width, height: i32) {
	return win.width, win.height
}

Window_Get_Aspect :: proc(win: ^Window) -> f32 {
	return win.aspect
}

// Call this in your resize callback or at the start of each frame
// if you support window resizing.
Window_Update_Size :: proc(win: ^Window) {
	w, h := glfw.GetWindowSize(win.handle)
	win.width  = w
	win.height = h
	if h > 0 {
		win.aspect = f32(w) / f32(h)
	}
	gl.Viewport(0, 0, w, h)
}

Window_Set_Title :: proc(win: ^Window, title: cstring) {
	win.title = title
	glfw.SetWindowTitle(win.handle, title)
}
