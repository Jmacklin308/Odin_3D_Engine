package engine

// =============================================================================
// Engine Config
//
// All engine-level configuration lives here. Sub-configs are defined in their
// respective files (e.g. WindowConfig in window.odin) and composed here.
//
// Usage:
//
//     cfg := eng.DEFAULT_CONFIG
//     cfg.debug.showGrid = true
//     eng.Init(cfg)
//
// =============================================================================

// -----------------------------------------------------------------------------
// Debug
// -----------------------------------------------------------------------------

DebugConfig :: struct {
	showGrid:       bool,
	gridHalfExtent: f32,  // world-space radius of the grid quad from camera centre
	gridColor:      Vec4, // RGBA — alpha is the base line opacity
	gridFadeStart:  f32,  // camera distance at which lines begin fading
	gridFadeEnd:    f32,  // camera distance at which lines are fully transparent
}

DEFAULT_DEBUG_CONFIG :: DebugConfig{
	showGrid       = false,
	gridHalfExtent = 100,
	gridColor      = {1, 1, 1, 0.4},
	gridFadeStart  = 20,
	gridFadeEnd    = 100,
}

// -----------------------------------------------------------------------------
// Root config — compose all sub-configs here
// -----------------------------------------------------------------------------

EngineConfig :: struct {
	window: WindowConfig,
	debug:  DebugConfig,
}

DEFAULT_CONFIG :: EngineConfig{
	window = DEFAULT_WINDOW_CONFIG,
	debug  = DEFAULT_DEBUG_CONFIG,
}
