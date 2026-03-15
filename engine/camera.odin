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

// =============================================================================
// Matrix Access
// Pass aspect = window.width / window.height.
// Matrices are lazily rebuilt; reading them is cheap when nothing has moved.
// =============================================================================

Camera_Get_View :: proc(cam: ^Camera) -> Mat4 {
	if cam.dirty do _camera_rebuild(cam, 0) // aspect not needed for view
	return cam.view
}

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

// =============================================================================
// Direction Vectors
// =============================================================================

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

// =============================================================================
// Movement
// These are intentionally low-level — call them from your player controller.
// Multiply delta by deltaTime and a speed scalar before passing in.
// =============================================================================

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

// =============================================================================
// FPS Input Helper
// Wraps the common "WASD + mouse look" pattern.
// Call every frame from your game loop.
// =============================================================================

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
