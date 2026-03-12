package engine

import "vendor:glfw"

// =============================================================================
// Constants
// Key and button codes are just GLFW constants re-exported for convenience.
// =============================================================================

// Keys — a selection of the most used ones. Full list: vendor/glfw/glfw3.h
KEY_UNKNOWN :: glfw.KEY_UNKNOWN
KEY_SPACE   :: glfw.KEY_SPACE
KEY_ESCAPE  :: glfw.KEY_ESCAPE
KEY_ENTER   :: glfw.KEY_ENTER
KEY_TAB     :: glfw.KEY_TAB
KEY_BACKSPACE :: glfw.KEY_BACKSPACE
KEY_LEFT    :: glfw.KEY_LEFT
KEY_RIGHT   :: glfw.KEY_RIGHT
KEY_UP      :: glfw.KEY_UP
KEY_DOWN    :: glfw.KEY_DOWN
KEY_LEFT_SHIFT   :: glfw.KEY_LEFT_SHIFT
KEY_LEFT_CONTROL :: glfw.KEY_LEFT_CONTROL
KEY_LEFT_ALT     :: glfw.KEY_LEFT_ALT

KEY_A :: glfw.KEY_A
KEY_B :: glfw.KEY_B
KEY_C :: glfw.KEY_C
KEY_D :: glfw.KEY_D
KEY_E :: glfw.KEY_E
KEY_F :: glfw.KEY_F
KEY_G :: glfw.KEY_G
KEY_H :: glfw.KEY_H
KEY_I :: glfw.KEY_I
KEY_J :: glfw.KEY_J
KEY_K :: glfw.KEY_K
KEY_L :: glfw.KEY_L
KEY_M :: glfw.KEY_M
KEY_N :: glfw.KEY_N
KEY_O :: glfw.KEY_O
KEY_P :: glfw.KEY_P
KEY_Q :: glfw.KEY_Q
KEY_R :: glfw.KEY_R
KEY_S :: glfw.KEY_S
KEY_T :: glfw.KEY_T
KEY_U :: glfw.KEY_U
KEY_V :: glfw.KEY_V
KEY_W :: glfw.KEY_W
KEY_X :: glfw.KEY_X
KEY_Y :: glfw.KEY_Y
KEY_Z :: glfw.KEY_Z

KEY_F1  :: glfw.KEY_F1
KEY_F2  :: glfw.KEY_F2
KEY_F3  :: glfw.KEY_F3
KEY_F4  :: glfw.KEY_F4
KEY_F5  :: glfw.KEY_F5
KEY_F6  :: glfw.KEY_F6
KEY_F7  :: glfw.KEY_F7
KEY_F8  :: glfw.KEY_F8
KEY_F9  :: glfw.KEY_F9
KEY_F10 :: glfw.KEY_F10
KEY_F11 :: glfw.KEY_F11
KEY_F12 :: glfw.KEY_F12

// Mouse buttons
MOUSE_LEFT   :: glfw.MOUSE_BUTTON_LEFT
MOUSE_RIGHT  :: glfw.MOUSE_BUTTON_RIGHT
MOUSE_MIDDLE :: glfw.MOUSE_BUTTON_MIDDLE

// Internal array sizes — large enough for all GLFW key/button codes.
@(private) KEY_COUNT   :: 512
@(private) MOUSE_COUNT :: 8

// =============================================================================
// Input State
// Stores current and previous frame state for both keyboard and mouse.
// Comparing current vs previous gives you pressed/released edge events.
// =============================================================================

Input :: struct {
	// Keyboard state — indexed by GLFW key code
	keys:     [KEY_COUNT]bool,
	prevKeys: [KEY_COUNT]bool,

	// Mouse cursor position in window pixels (top-left origin)
	mousePos:     Vec2,
	prevMousePos: Vec2,
	mouseDelta:   Vec2, // How far the cursor moved this frame

	// Mouse button state — indexed by GLFW mouse button code
	mouseButtons:     [MOUSE_COUNT]bool,
	prevMouseButtons: [MOUSE_COUNT]bool,

	scrollDelta: Vec2, // Scroll wheel: x = horizontal, y = vertical

	// When true the cursor is hidden and confined to the window.
	// Mouse delta still works — use it for FPS camera rotation.
	cursorLocked: bool,

	// Internal flag to discard the first delta after cursor lock is toggled.
	// Without this you get one monster jump frame that sends your camera to Mars.
	firstMouseFrame: bool,
}

// =============================================================================
// Input Update — call once per frame before reading any input state
// =============================================================================

// Polls GLFW for current input state and computes per-frame deltas.
Input_Update :: proc(input: ^Input, win: ^Window) {
	// Shift current → previous
	input.prevKeys        = input.keys
	input.prevMouseButtons = input.mouseButtons
	input.prevMousePos    = input.mousePos

	// Poll keyboard
	for key in 0..<KEY_COUNT {
		input.keys[key] = glfw.GetKey(win.handle, i32(key)) == glfw.PRESS
	}

	// Poll mouse buttons
	for btn in 0..<MOUSE_COUNT {
		input.mouseButtons[btn] = glfw.GetMouseButton(win.handle, i32(btn)) == glfw.PRESS
	}

	// Cursor position
	cx, cy := glfw.GetCursorPos(win.handle)
	input.mousePos = Vec2{f32(cx), f32(cy)}

	if input.firstMouseFrame {
		// First frame after locking: swallow the delta to prevent the camera snap
		input.prevMousePos  = input.mousePos
		input.firstMouseFrame = false
	}

	input.mouseDelta = input.mousePos - input.prevMousePos

	// Scroll delta is set via the scroll callback (see Input_Setup_Callbacks).
	// It gets cleared at the top of each update so it only lives one frame.
}

// Attach GLFW callbacks for scroll input.
// Call once after creating the window.
Input_Setup_Callbacks :: proc(input: ^Input, win: ^Window) {
	// Store a pointer to our Input in the GLFW window user pointer slot.
	// The scroll callback retrieves it from there.
	glfw.SetWindowUserPointer(win.handle, input)
	glfw.SetScrollCallback(win.handle, _scroll_callback)
}

@(private)
_scroll_callback :: proc "c" (window: glfw.WindowHandle, xOffset, yOffset: f64) {
	input := (^Input)(glfw.GetWindowUserPointer(window))
	if input == nil do return
	input.scrollDelta.x += f32(xOffset)
	input.scrollDelta.y += f32(yOffset)
}

// Clear scroll delta — call at the start of each frame before Input_Update.
Input_Clear_Frame :: proc(input: ^Input) {
	input.scrollDelta = {}
}

// =============================================================================
// Keyboard Queries
// =============================================================================

// True every frame while the key is held down.
Input_Key_Down :: proc(input: ^Input, key: i32) -> bool {
	if key < 0 || int(key) >= KEY_COUNT do return false
	return input.keys[key]
}

// True only on the first frame the key is pressed. Edge trigger.
Input_Key_Pressed :: proc(input: ^Input, key: i32) -> bool {
	if key < 0 || int(key) >= KEY_COUNT do return false
	return input.keys[key] && !input.prevKeys[key]
}

// True only on the first frame the key is released. Edge trigger.
Input_Key_Released :: proc(input: ^Input, key: i32) -> bool {
	if key < 0 || int(key) >= KEY_COUNT do return false
	return !input.keys[key] && input.prevKeys[key]
}

// =============================================================================
// Mouse Queries
// =============================================================================

// True every frame while the mouse button is held down.
Input_Mouse_Down :: proc(input: ^Input, button: i32) -> bool {
	if button < 0 || int(button) >= MOUSE_COUNT do return false
	return input.mouseButtons[button]
}

// True only on the first frame the button is clicked.
Input_Mouse_Pressed :: proc(input: ^Input, button: i32) -> bool {
	if button < 0 || int(button) >= MOUSE_COUNT do return false
	return input.mouseButtons[button] && !input.prevMouseButtons[button]
}

// True only on the first frame the button is released.
Input_Mouse_Released :: proc(input: ^Input, button: i32) -> bool {
	if button < 0 || int(button) >= MOUSE_COUNT do return false
	return !input.mouseButtons[button] && input.prevMouseButtons[button]
}

// Mouse movement since last frame. Useful for camera look-around.
Input_Mouse_Delta :: proc(input: ^Input) -> Vec2 {
	return input.mouseDelta
}

// Scroll wheel delta this frame. y > 0 = scrolled up/forward.
Input_Scroll_Delta :: proc(input: ^Input) -> Vec2 {
	return input.scrollDelta
}

// =============================================================================
// Cursor Control
// =============================================================================

// Lock or unlock the cursor. Locked = hidden + confined, great for FPS cameras.
Input_Set_Cursor_Locked :: proc(input: ^Input, win: ^Window, locked: bool) {
	input.cursorLocked = locked
	if locked {
		glfw.SetInputMode(win.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
		input.firstMouseFrame = true // Ignore the first delta after locking
	} else {
		glfw.SetInputMode(win.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
	}
}
