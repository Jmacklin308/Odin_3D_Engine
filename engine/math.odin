package engine

import "core:math"
import "core:math/linalg"

// =============================================================================
// Types
// =============================================================================

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

// Transform holds position, rotation, and scale in one tidy package.
// Build a model matrix from it with Transform_To_Mat4.
Transform :: struct {
	position: Vec3,
	rotation: Quat,
	scale:    Vec3,
}

// =============================================================================
// Constants
// =============================================================================

VEC2_ZERO :: Vec2{0, 0}
VEC2_ONE  :: Vec2{1, 1}

VEC3_ZERO    :: Vec3{0, 0, 0}
VEC3_ONE     :: Vec3{1, 1, 1}
VEC3_UP      :: Vec3{0, 1, 0}
VEC3_DOWN    :: Vec3{0, -1, 0}
VEC3_RIGHT   :: Vec3{1, 0, 0}
VEC3_LEFT    :: Vec3{-1, 0, 0}
VEC3_FORWARD :: Vec3{0, 0, -1} // OpenGL: -Z is forward
VEC3_BACK    :: Vec3{0, 0, 1}

MAT4_IDENTITY :: Mat4{
	1, 0, 0, 0,
	0, 1, 0, 0,
	0, 0, 1, 0,
	0, 0, 0, 1,
}

QUAT_IDENTITY :: Quat(1)

// =============================================================================
// Vec2 Operations
// =============================================================================

Vec2_Length :: proc(v: Vec2) -> f32 {
	return linalg.length(v)
}

Vec2_Normalize :: proc(v: Vec2) -> Vec2 {
	return linalg.normalize(v)
}

Vec2_Dot :: proc(a, b: Vec2) -> f32 {
	return linalg.dot(a, b)
}

// =============================================================================
// Vec3 Operations
// =============================================================================

Vec3_Normalize :: proc(v: Vec3) -> Vec3 {
	return linalg.normalize(v)
}

Vec3_Dot :: proc(a, b: Vec3) -> f32 {
	return linalg.dot(a, b)
}

Vec3_Cross :: proc(a, b: Vec3) -> Vec3 {
	return linalg.cross(a, b)
}

Vec3_Length :: proc(v: Vec3) -> f32 {
	return linalg.length(v)
}

// Squared length — use this when you only need to compare distances.
// Avoids a sqrt call, which your CPU will appreciate.
Vec3_Length_Sq :: proc(v: Vec3) -> f32 {
	return linalg.length2(v)
}

Vec3_Distance :: proc(a, b: Vec3) -> f32 {
	return linalg.length(b - a)
}

Vec3_Lerp :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return linalg.lerp(a, b, t)
}

Vec3_Reflect :: proc(v, normal: Vec3) -> Vec3 {
	return linalg.reflect(v, normal)
}

// =============================================================================
// Mat4 Operations
// =============================================================================

// Perspective projection matrix.
// fovY is in radians. aspect = width/height. near/far are clip plane distances.
Mat4_Perspective :: proc(fovY, aspect, near, far: f32) -> Mat4 {
	return linalg.matrix4_perspective_f32(fovY, aspect, near, far, false)
}

// View matrix: positions the camera at `eye` looking toward `target`.
Mat4_Look_At :: proc(eye, target, up: Vec3) -> Mat4 {
	return linalg.matrix4_look_at_f32(eye, target, up)
}

Mat4_Translate :: proc(v: Vec3) -> Mat4 {
	return linalg.matrix4_translate_f32(v)
}

Mat4_Scale :: proc(v: Vec3) -> Mat4 {
	return linalg.matrix4_scale_f32(v)
}

// Rotation matrix from angle in radians around an arbitrary axis.
Mat4_Rotate :: proc(angle: f32, axis: Vec3) -> Mat4 {
	return linalg.matrix4_rotate_f32(angle, axis)
}

Mat4_From_Quat :: proc(q: Quat) -> Mat4 {
	return linalg.matrix4_from_quaternion_f32(q)
}

// Build a Transform-Rotate-Scale matrix in one shot.
Mat4_TRS :: proc(pos: Vec3, rot: Quat, scl: Vec3) -> Mat4 {
	t := Mat4_Translate(pos)
	r := Mat4_From_Quat(rot)
	s := Mat4_Scale(scl)
	return t * r * s
}

Mat4_Inverse :: proc(m: Mat4) -> Mat4 {
	return linalg.inverse(m)
}

Mat4_Transpose :: proc(m: Mat4) -> Mat4 {
	return linalg.transpose(m)
}

// The normal matrix: inverse-transpose of the model matrix.
// Required to correctly transform normals when the mesh has non-uniform scale.
// If your scale is always uniform, the model matrix itself is fine.
Mat4_Normal :: proc(model: Mat4) -> Mat4 {
	return Mat4_Transpose(Mat4_Inverse(model))
}

// =============================================================================
// Quaternion Operations
// =============================================================================

// Create a quaternion from an axis (normalized) and an angle in radians.
Quat_Axis_Angle :: proc(axis: Vec3, angle: f32) -> Quat {
	return linalg.quaternion_angle_axis_f32(angle, axis)
}

// Build a quaternion from Euler angles in radians.
// Order: yaw (Y) applied first, then pitch (X), then roll (Z).
// This is standard FPS camera convention.
Quat_From_Euler :: proc(pitch, yaw, roll: f32) -> Quat {
	qYaw   := Quat_Axis_Angle(VEC3_UP, yaw)
	qPitch := Quat_Axis_Angle(VEC3_RIGHT, pitch)
	qRoll  := Quat_Axis_Angle(VEC3_FORWARD, roll)
	return linalg.normalize(qYaw * qPitch * qRoll)
}

Quat_Normalize :: proc(q: Quat) -> Quat {
	return linalg.normalize(q)
}

// Normalized linear interpolation between two quaternions.
// Faster than true slerp and visually identical for small angles.
Quat_Nlerp :: proc(a, b: Quat, t: f32) -> Quat {
	result := linalg.lerp(a, b, t)
	return linalg.normalize(result)
}

// Rotate a direction vector by a quaternion.
Quat_Rotate_Vec3 :: proc(q: Quat, v: Vec3) -> Vec3 {
	m := Mat4_From_Quat(q)
	r := m * Vec4{v.x, v.y, v.z, 0}
	return Vec3{r.x, r.y, r.z}
}

// =============================================================================
// Transform Helpers
// =============================================================================

Transform_Default :: proc() -> Transform {
	return Transform{
		position = VEC3_ZERO,
		rotation = QUAT_IDENTITY,
		scale    = VEC3_ONE,
	}
}

Transform_To_Mat4 :: proc(t: Transform) -> Mat4 {
	return Mat4_TRS(t.position, t.rotation, t.scale)
}

// =============================================================================
// Scalar Utilities
// =============================================================================

To_Radians :: proc(degrees: f32) -> f32 {
	return math.to_radians(degrees)
}

To_Degrees :: proc(radians: f32) -> f32 {
	return math.to_degrees(radians)
}

// Smooth step — eases in and out between 0 and 1. Great for animations.
Smooth_Step :: proc(edge0, edge1, x: f32) -> f32 {
	t := clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
}

F32_Lerp :: proc(a, b, t: f32) -> f32 {
	return a + t * (b - a)
}
