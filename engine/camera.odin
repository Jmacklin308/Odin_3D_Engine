package engine

import "core:math"

// =============================================================================
// Camera
//
// FPS-style camera with yaw/pitch rotation.
// Pitch is clamped so you can't flip upside down — unless you override pitchLimit,
// in which case your motion sickness is your own business.
// =============================================================================

Camera :: struct {
	position:   Vec3,
	yaw:        f32, // Rotation around the world Y axis, in radians
	pitch:      f32, // Rotation around the local X axis, in radians
	fovY:       f32, // Vertical field of view in radians
	nearPlane:  f32,
	farPlane:   f32,
	pitchLimit: f32, // Max absolute pitch in radians. Default: ~89°

	// Cached matrices — rebuilt automatically when dirty.
	// Reading view/projection always returns up-to-date values.
	view:       Mat4,
	projection: Mat4,
	dirty:      bool, // true = matrices need recalculation
}

// Create a camera positioned at `pos`, looking along -Z.
// fovY is in degrees and will be converted internally.
Camera_Create :: proc(pos: Vec3, fovYDegrees: f32 = 75, near: f32 = 0.1, far: f32 = 3500) -> Camera {
	cam := Camera{
		position   = pos,
		yaw        = 0,
		pitch      = 0,
		fovY       = To_Radians(fovYDegrees),
		nearPlane  = near,
		farPlane   = far,
		pitchLimit = To_Radians(89),
		dirty      = true,
	}
	return cam
}

// Returns the camera view matrix.
Camera_Get_View :: proc(cam: ^Camera) -> Mat4 {
	if cam.dirty do _camera_rebuild(cam, 0) // aspect not needed for view
	return cam.view
}

// Returns the camera projection matrix for the given aspect ratio.
Camera_Get_Projection :: proc(cam: ^Camera, aspect: f32) -> Mat4 {
	// Projection always needs the current aspect, so always rebuild it.
	cam.projection = Mat4_Perspective(cam.fovY, aspect, cam.nearPlane, cam.farPlane)
	return cam.projection
}

// Returns both matrices in one call. Slightly more convenient.
Camera_Get_VP :: proc(cam: ^Camera, aspect: f32) -> (view, proj: Mat4) {
	_camera_rebuild(cam, aspect)
	return cam.view, cam.projection
}

// The direction the camera is pointing (normalised).
Camera_Get_Forward :: proc(cam: ^Camera) -> Vec3 {
	return Vec3{
		math.cos(cam.pitch) * math.sin(cam.yaw),
		math.sin(cam.pitch),
		-math.cos(cam.pitch) * math.cos(cam.yaw),
	}
}

// The local right vector of the camera (normalised).
Camera_Get_Right :: proc(cam: ^Camera) -> Vec3 {
	forward := Camera_Get_Forward(cam)
	return Vec3_Normalize(Vec3_Cross(forward, VEC3_UP))
}

// Move the camera by a world-space offset.
Camera_Move :: proc(cam: ^Camera, delta: Vec3) {
	cam.position += delta
	cam.dirty = true
}

// Move along the camera's local axes (forward/right/up).
// W/S moves in the full 3D direction the camera faces (including pitch).
// Q/E moves along the camera's local up, so it tilts with the pitch.
Camera_Move_Local :: proc(cam: ^Camera, forward, right, up: f32) {
	fwd := Camera_Get_Forward(cam)
	rgt := Camera_Get_Right(cam)
	upr := Vec3_Normalize(Vec3_Cross(rgt, fwd))

	cam.position += fwd * forward
	cam.position += rgt * right
	cam.position += upr * up
	cam.dirty = true
}

// Apply yaw (horizontal) and pitch (vertical) rotation in radians.
// Typically driven by mouse delta × sensitivity.
Camera_Rotate :: proc(cam: ^Camera, yawDelta, pitchDelta: f32) {
	cam.yaw   += yawDelta
	cam.pitch += pitchDelta

	// Clamp pitch so you can't look past straight up or down.
	cam.pitch = clamp(cam.pitch, -cam.pitchLimit, cam.pitchLimit)
	
	

	// Keep yaw in [0, 2π] to avoid floating-point drift over a long session.
	TWO_PI :: 6.28318530718
	for cam.yaw > TWO_PI  do cam.yaw -= TWO_PI
	for cam.yaw < 0       do cam.yaw += TWO_PI

	cam.dirty = true
}

// Snap the camera to look directly at a world-space point.
Camera_Look_At :: proc(cam: ^Camera, target: Vec3) {
	dir   := Vec3_Normalize(target - cam.position)
	cam.pitch = math.asin(dir.y)
	cam.yaw   = math.atan2(dir.x, -dir.z)
	cam.dirty = true
}

CameraFPSParams :: struct {
	moveSpeed:    f32, // Units per second for WASD movement
	mouseSensitivity: f32, // Radians per pixel of mouse movement
	sprintMult:   f32, // Speed multiplier when shift is held. 1.0 = no sprint.
}

DEFAULT_FPS_PARAMS :: CameraFPSParams{
	moveSpeed        = 10,
	mouseSensitivity = 0.002,
	sprintMult       = 3.0,
}

CameraOrbitZoomState :: struct {
	active:         bool,
	focusPoint:     Vec3,
	targetDistance: f32,
}

// Applies the built-in WASD, mouse-look, and sprint camera controls.
// Always active — use Camera_FPS_Update_RMB for Unity/Godot-style right-click-to-look.
Camera_FPS_Update :: proc(cam: ^Camera, input: ^Input, dt: f32, params: CameraFPSParams = DEFAULT_FPS_PARAMS) {
	// Mouse look
	delta := Input_Mouse_Delta(input)
	Camera_Rotate(cam, delta.x * params.mouseSensitivity, -delta.y * params.mouseSensitivity)

	// Movement
	speed := params.moveSpeed
	if Input_Key_Down(input, KEY_LEFT_SHIFT) {
		speed *= params.sprintMult
	}

	fwd   : f32 = 0
	rgt   : f32 = 0
	vert  : f32 = 0

	if Input_Key_Down(input, KEY_W) do fwd  += speed * dt
	if Input_Key_Down(input, KEY_S) do fwd  -= speed * dt
	if Input_Key_Down(input, KEY_D) do rgt  += speed * dt
	if Input_Key_Down(input, KEY_A) do rgt  -= speed * dt
	if Input_Key_Down(input, KEY_E) do vert += speed * dt
	if Input_Key_Down(input, KEY_Q) do vert -= speed * dt

	Camera_Move_Local(cam, fwd, rgt, vert)
}

// Unity/Godot-style camera: only rotates and moves while right mouse button is held.
// Locks the cursor on right-down, restores it on right-up.
// Left-click and other interactions remain available when RMB is not held.
Camera_FPS_Update_RMB :: proc(cam: ^Camera, input: ^Input, win: ^Window, dt: f32, params: CameraFPSParams = DEFAULT_FPS_PARAMS) {
	rmbDown     := Input_Mouse_Down(input, MOUSE_RIGHT)
	rmbPressed  := Input_Mouse_Pressed(input, MOUSE_RIGHT)
	rmbReleased := Input_Mouse_Released(input, MOUSE_RIGHT)

	// Lock cursor when RMB is first pressed, unlock when released.
	if rmbPressed  do Input_Set_Cursor_Locked(input, win, true)
	if rmbReleased do Input_Set_Cursor_Locked(input, win, false)

	if !rmbDown do return

	// Mouse look — only while held.
	delta := Input_Mouse_Delta(input)
	Camera_Rotate(cam, delta.x * params.mouseSensitivity, -delta.y * params.mouseSensitivity)

	// Movement — only while held.
	speed := params.moveSpeed
	if Input_Key_Down(input, KEY_LEFT_SHIFT) do speed *= params.sprintMult

	fwd  : f32 = 0
	rgt  : f32 = 0
	vert : f32 = 0

	if Input_Key_Down(input, KEY_W) do fwd  += speed * dt
	if Input_Key_Down(input, KEY_S) do fwd  -= speed * dt
	if Input_Key_Down(input, KEY_D) do rgt  += speed * dt
	if Input_Key_Down(input, KEY_A) do rgt  -= speed * dt
	if Input_Key_Down(input, KEY_E) do vert += speed * dt
	if Input_Key_Down(input, KEY_Q) do vert -= speed * dt

	Camera_Move_Local(cam, fwd, rgt, vert)
}

// Orbits around a world-space target while right mouse is held.
// The target remains centred by preserving the current camera-target distance.
Camera_Orbit_Update_RMB :: proc(cam: ^Camera, input: ^Input, win: ^Window, target: Vec3, recenter: bool = false, params: CameraFPSParams = DEFAULT_FPS_PARAMS) {
	rmbDown     := Input_Mouse_Down(input, MOUSE_RIGHT)
	rmbPressed  := Input_Mouse_Pressed(input, MOUSE_RIGHT)
	rmbReleased := Input_Mouse_Released(input, MOUSE_RIGHT)

	if rmbPressed || (rmbDown && recenter) {
		Camera_Look_At(cam, target)
		Input_Set_Cursor_Locked(input, win, true)
	}
	if rmbReleased do Input_Set_Cursor_Locked(input, win, false)

	if !rmbDown do return

	distance := Vec3_Distance(cam.position, target)
	if distance < 0.001 do distance = 0.001

	delta := Input_Mouse_Delta(input)
	Camera_Rotate(cam, delta.x * params.mouseSensitivity, -delta.y * params.mouseSensitivity)

	forward := Camera_Get_Forward(cam)
	cam.position = target - forward * distance
	cam.dirty = true
}

Camera_Orbit_Zoom_Update :: proc(zoom: ^CameraOrbitZoomState, cam: ^Camera, target: Vec3, radius: f32, scrollY, dt: f32, linearZoom: bool = false) {
	currentDistance := Vec3_Distance(cam.position, target)
	if currentDistance < 0.001 do currentDistance = 0.001

	halfTan := math.tan(cam.fovY * 0.5)
	fillDistance := radius / (halfTan * 0.96)
	minDistance := math.max(math.max(radius * 1.05 + 0.1, fillDistance), 0.2)
	maxDistance := math.max(minDistance, cam.farPlane * 0.95)

	if scrollY != 0 {
		if !zoom.active {
			forward := Camera_Get_Forward(cam)
			zoom.focusPoint = cam.position + forward * currentDistance
			zoom.targetDistance = currentDistance
		}
		ZOOM_IN_STEP_MIN  :: f32(0.055)
		ZOOM_IN_STEP_MAX  :: f32(0.86)
		ZOOM_OUT_STEP     :: f32(0.55)
		ZOOM_LINEAR_STEP  :: f32(0.9)

		step: f32
		if linearZoom {
			step = ZOOM_LINEAR_STEP
		} else if scrollY > 0 {
			distanceRatio := zoom.targetDistance / minDistance
			room := clamp((distanceRatio - 1.0) / 1.5, 0, 1)
			step = ZOOM_IN_STEP_MIN + (ZOOM_IN_STEP_MAX - ZOOM_IN_STEP_MIN) * room
		} else {
			step = ZOOM_OUT_STEP
		}
		zoom.targetDistance *= math.exp(-scrollY * step)
		zoom.targetDistance = clamp(zoom.targetDistance, minDistance, maxDistance)
		zoom.active = true
	}

	if !zoom.active do return

	t := f32(1) - math.exp(-12.0 * dt)
	zoom.focusPoint = Vec3_Lerp(zoom.focusPoint, target, t)

	focusDistance := Vec3_Distance(cam.position, zoom.focusPoint)
	if focusDistance < 0.001 do focusDistance = 0.001

	distance := focusDistance + (zoom.targetDistance - focusDistance) * t
	distance = clamp(distance, minDistance, maxDistance)

	Camera_Look_At(cam, zoom.focusPoint)
	forward := Camera_Get_Forward(cam)
	cam.position = zoom.focusPoint - forward * distance
	cam.dirty = true

	if Vec3_Distance(zoom.focusPoint, target) < 0.001 && math.abs(distance - zoom.targetDistance) < 0.001 {
		zoom.focusPoint = target
		Camera_Look_At(cam, zoom.focusPoint)
		forward = Camera_Get_Forward(cam)
		cam.position = zoom.focusPoint - forward * zoom.targetDistance
		cam.dirty = true
		zoom.active = false
	}
}

Camera_Orbit_Zoom_Cancel :: proc(zoom: ^CameraOrbitZoomState) {
	zoom.active = false
}

// =============================================================================
// Focus Animation
//
// Smoothly flies the camera to frame a world-space target sphere.
// Typical use: press F in the editor to focus on the selected objects.
// =============================================================================

Camera_Focus_State :: struct {
	active:      bool,
	targetPos:   Vec3,
	targetYaw:   f32,
	targetPitch: f32,
}

@(private)
_FOCUS_SPEED :: f32(7.0) // exponential approach speed (units/s feel)

// Distance used for the close-up double-tap focus.
CAMERA_FOCUS_CLOSE_DISTANCE :: f32(1.0)

// Begin a smooth focus animation toward `target`, framing a sphere of `radius`.
// The camera re-orients to look directly at the target and backs off to a
// distance where the bounding sphere fills ~75 % of the vertical FOV.
Camera_Focus_Begin :: proc(focus: ^Camera_Focus_State, cam: ^Camera, target: Vec3, radius: f32) {
	// Distance so the sphere fills 75 % of the vertical view height.
	// tan(fovY/2) * d * 0.75 = radius  →  d = radius / (tan(fovY/2) * 0.75)
	halfTan    := math.tan(cam.fovY * 0.5)
	targetDist := radius / (halfTan * 0.75)
	targetDist  = math.max(targetDist, radius * 1.2 + 0.5) // stay clear of the objects
	_camera_focus_begin_at(focus, cam, target, radius, targetDist)
}

// Begin a smooth close-up focus animation, stopping ~5 m from the target centre.
// Clamped so the camera never clips into the bounding sphere of the selection.
Camera_Focus_Begin_Close :: proc(focus: ^Camera_Focus_State, cam: ^Camera, target: Vec3, radius: f32) {
	targetDist := math.max(CAMERA_FOCUS_CLOSE_DISTANCE, radius * 1.2 + 0.2)
	_camera_focus_begin_at(focus, cam, target, radius, targetDist)
}

@(private)
_camera_focus_begin_at :: proc(focus: ^Camera_Focus_State, cam: ^Camera, target: Vec3, radius: f32, dist: f32) {
	toTarget := target - cam.position
	dir: Vec3
	if Vec3_Length_Sq(toTarget) < 1e-4 {
		dir = Camera_Get_Forward(cam)
	} else {
		dir = Vec3_Normalize(toTarget)
	}

	focus.targetPos   = target - dir * dist
	focus.targetPitch = math.asin(clamp(dir.y, f32(-1), f32(1)))
	focus.targetYaw   = math.atan2(dir.x, -dir.z)

	// Normalise targetYaw to [0, 2π] to match the camera convention.
	TWO_PI :: f32(6.28318530718)
	for focus.targetYaw < 0      do focus.targetYaw += TWO_PI
	for focus.targetYaw > TWO_PI do focus.targetYaw -= TWO_PI

	focus.active = true
}

// Animate the camera one step toward its focus target.  Call every frame.
// The animation stops automatically once the camera is settled.
Camera_Focus_Update :: proc(focus: ^Camera_Focus_State, cam: ^Camera, dt: f32) {
	if !focus.active do return

	t := f32(1) - math.exp(-_FOCUS_SPEED * dt)

	cam.position = Vec3_Lerp(cam.position, focus.targetPos, t)

	// Shortest-arc yaw interpolation.
	TWO_PI :: f32(6.28318530718)
	yawDiff := focus.targetYaw - cam.yaw
	for yawDiff >  math.PI do yawDiff -= TWO_PI
	for yawDiff < -math.PI do yawDiff += TWO_PI
	cam.yaw += yawDiff * t
	for cam.yaw > TWO_PI do cam.yaw -= TWO_PI
	for cam.yaw < 0      do cam.yaw += TWO_PI

	cam.pitch = cam.pitch + (focus.targetPitch - cam.pitch) * t
	cam.pitch = clamp(cam.pitch, -cam.pitchLimit, cam.pitchLimit)
	cam.dirty = true

	// Settle: snap to target once close enough.
	posDelta  := Vec3_Length(cam.position - focus.targetPos)
	yawDiff2  := focus.targetYaw - cam.yaw
	for yawDiff2 >  math.PI do yawDiff2 -= TWO_PI
	for yawDiff2 < -math.PI do yawDiff2 += TWO_PI
	pitchDiff := math.abs(focus.targetPitch - cam.pitch)
	if posDelta < 0.01 && math.abs(yawDiff2) < 0.001 && pitchDiff < 0.001 {
		cam.position = focus.targetPos
		cam.yaw      = focus.targetYaw
		cam.pitch    = clamp(focus.targetPitch, -cam.pitchLimit, cam.pitchLimit)
		cam.dirty    = true
		focus.active = false
	}
}

// Interrupt a running focus animation (e.g. when the user starts flying).
Camera_Focus_Cancel :: proc(focus: ^Camera_Focus_State) {
	focus.active = false
}

// =============================================================================
// Internal
// =============================================================================

@(private)
_camera_rebuild :: proc(cam: ^Camera, aspect: f32) {
	forward := Camera_Get_Forward(cam)
	cam.view = Mat4_Look_At(cam.position, cam.position + forward, VEC3_UP)
	if aspect > 0 {
		cam.projection = Mat4_Perspective(cam.fovY, aspect, cam.nearPlane, cam.farPlane)
	}
	cam.dirty = false
}
