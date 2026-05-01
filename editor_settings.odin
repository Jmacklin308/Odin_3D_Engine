package main

import eng "engine"
import rend "renderer"
import "core:fmt"
import "core:mem"
import "core:os"

EDITOR_SETTINGS_PATH :: "editor_settings.o3dcfg"

Editor_Clear_Theme :: enum u8 {
	DEEP,
	GRAPHITE,
	DAWN,
}

Editor_Settings :: struct {
	showGrid:         bool,
	vsync:            bool,
	cameraSpeed:      f32,
	mouseSensitivity: f32,
	editorScale:      f32,
	clearTheme:       Editor_Clear_Theme,
}

@(private = "file")
EDITOR_SETTINGS_MAGIC :: [4]u8{'O', '3', 'C', 'F'}

@(private = "file")
EDITOR_SETTINGS_VERSION :: u32(1)

@(private = "file")
_Editor_Settings_Record :: struct #packed {
	magic:            [4]u8,
	version:          u32,
	showGrid:         u8,
	vsync:            u8,
	clearTheme:       u8,
	_reserved0:       u8,
	cameraSpeed:      f32,
	mouseSensitivity: f32,
	editorScale:      f32,
	_reserved1:       [40]u8,
}

#assert(size_of(_Editor_Settings_Record) == 64)

Editor_Settings_Default :: proc() -> Editor_Settings {
	return {
		showGrid         = true,
		vsync            = false,
		cameraSpeed      = eng.DEFAULT_FPS_PARAMS.moveSpeed,
		mouseSensitivity = eng.DEFAULT_FPS_PARAMS.mouseSensitivity,
		editorScale      = 1.0,
		clearTheme       = .DEEP,
	}
}

Editor_Settings_Load :: proc(path: string = EDITOR_SETTINGS_PATH) -> (settings: Editor_Settings, loaded: bool) {
	settings = Editor_Settings_Default()

	data, ok := os.read_entire_file(path)
	if !ok do return settings, false
	defer delete(data)

	if len(data) < size_of(_Editor_Settings_Record) {
		fmt.eprintf("[Editor Settings] '%s' is too small; using defaults.\n", path)
		return settings, false
	}

	rec := (^_Editor_Settings_Record)(&data[0])^
	if rec.magic != EDITOR_SETTINGS_MAGIC || rec.version != EDITOR_SETTINGS_VERSION {
		fmt.eprintf("[Editor Settings] '%s' has an unsupported format; using defaults.\n", path)
		return settings, false
	}

	settings.showGrid         = rec.showGrid != 0
	settings.vsync            = rec.vsync != 0
	settings.cameraSpeed      = clamp(rec.cameraSpeed, 2.0, 80.0)
	settings.mouseSensitivity = clamp(rec.mouseSensitivity, 0.0005, 0.01)
	settings.editorScale      = rec.editorScale
	if settings.editorScale == 0 do settings.editorScale = 1.0
	settings.editorScale = clamp(settings.editorScale, 0.75, 1.75)
	settings.clearTheme       = Editor_Clear_Theme(rec.clearTheme)
	if settings.clearTheme > .DAWN do settings.clearTheme = .DEEP

	return settings, true
}

Editor_Settings_Save :: proc(settings: ^Editor_Settings, path: string = EDITOR_SETTINGS_PATH) -> bool {
	rec := _Editor_Settings_Record{
		magic            = EDITOR_SETTINGS_MAGIC,
		version          = EDITOR_SETTINGS_VERSION,
		showGrid         = settings.showGrid ? 1 : 0,
		vsync            = settings.vsync ? 1 : 0,
		clearTheme       = u8(settings.clearTheme),
		cameraSpeed      = settings.cameraSpeed,
		mouseSensitivity = settings.mouseSensitivity,
		editorScale      = settings.editorScale,
	}

	bytes := make([]u8, size_of(_Editor_Settings_Record))
	defer delete(bytes)
	mem.copy(&bytes[0], &rec, size_of(_Editor_Settings_Record))

	if !os.write_entire_file(path, bytes) {
		fmt.eprintf("[Editor Settings] Failed to write '%s'.\n", path)
		return false
	}
	return true
}

Editor_Settings_Apply_Config :: proc(settings: ^Editor_Settings, cfg: ^eng.EngineConfig) {
	cfg.debug.showGrid = settings.showGrid
	cfg.window.vsync   = settings.vsync
}

Editor_Settings_Camera_Params :: proc(settings: ^Editor_Settings) -> eng.CameraFPSParams {
	return {
		moveSpeed        = settings.cameraSpeed,
		mouseSensitivity = settings.mouseSensitivity,
		sprintMult       = eng.DEFAULT_FPS_PARAMS.sprintMult,
	}
}

Editor_Settings_Clear_Color :: proc(settings: ^Editor_Settings) -> eng.Vec4 {
	switch settings.clearTheme {
	case .GRAPHITE:
		return {0.075, 0.080, 0.088, 1.0}
	case .DAWN:
		return {0.16, 0.13, 0.11, 1.0}
	case .DEEP:
		return {0.055, 0.065, 0.090, 1.0}
	}
	return {0.055, 0.065, 0.090, 1.0}
}

Editor_Settings_Clear_Label :: proc(theme: Editor_Clear_Theme) -> string {
	switch theme {
	case .GRAPHITE: return "GRAPHITE"
	case .DAWN:     return "DAWN"
	case .DEEP:     return "DEEP"
	}
	return "DEEP"
}

Editor_Settings_Draw_Menu :: proc(
	ui:          ^rend.UI_Context,
	settings:    ^Editor_Settings,
	notifications: ^rend.Notification_Tray,
	r:           ^rend.Renderer,
	win:         ^eng.Window,
	screenSize:  eng.Vec2,
) {
	panelW := f32(336.0)
	panelH := f32(326.0)
	x := screenSize.x - panelW - 14.0
	y := f32(64.0)

	rend.UI_Panel(ui, {x, y, panelW, panelH})
	rend.UI_Label(ui, {x + 18, y + 18}, "SETTINGS", 2.0)
	rend.UI_Label(ui, {x + 18, y + 42}, "EDITOR PREFERENCES", 1.35, ui.theme.textMuted)

	changed := false
	notifySave := true

	if rend.UI_Toggle(ui, "settings_grid", {x + 18, y + 72, 142, 30}, "GRID", settings.showGrid) {
		settings.showGrid = !settings.showGrid
		eng.Set_Debug_Show_Grid(settings.showGrid)
		changed = true
	}
	if rend.UI_Toggle(ui, "settings_vsync", {x + 176, y + 72, 142, 30}, "VSYNC", settings.vsync) {
		settings.vsync = !settings.vsync
		eng.Window_Set_VSync(win, settings.vsync)
		changed = true
	}

	rend.UI_Label(ui, {x + 18, y + 122}, "CAMERA SPEED", 1.45, ui.theme.textMuted)
	rend.UI_Label(ui, {x + 178, y + 122}, fmt.tprintf("%.0f M/S", settings.cameraSpeed), 1.45, ui.theme.text)
	if rend.UI_Button(ui, "settings_speed_down", {x + 18, y + 144, 44, 30}, "-", false) {
		settings.cameraSpeed = clamp(settings.cameraSpeed - 2.0, 2.0, 80.0)
		changed = true
	}
	if rend.UI_Button(ui, "settings_speed_up", {x + 74, y + 144, 44, 30}, "+", false) {
		settings.cameraSpeed = clamp(settings.cameraSpeed + 2.0, 2.0, 80.0)
		changed = true
	}

	rend.UI_Label(ui, {x + 18, y + 188}, "EDITOR SCALE", 1.45, ui.theme.textMuted)
	rend.UI_Label(ui, {x + 178, y + 188}, fmt.tprintf("%.0f%%", settings.editorScale * 100.0), 1.45, ui.theme.text)
	if rend.UI_Slider(ui, "settings_editor_scale", {x + 18, y + 212, 300, 30}, &settings.editorScale, 0.75, 1.75) {
		settings.editorScale = clamp(settings.editorScale, 0.75, 1.75)
		changed = true
		notifySave = false
	}

	rend.UI_Label(ui, {x + 18, y + 258}, "LOOK SENSITIVITY", 1.45, ui.theme.textMuted)
	rend.UI_Label(ui, {x + 178, y + 258}, fmt.tprintf("%.3f", settings.mouseSensitivity), 1.45, ui.theme.text)
	if rend.UI_Button(ui, "settings_sens_down", {x + 18, y + 280, 44, 30}, "-", false) {
		settings.mouseSensitivity = clamp(settings.mouseSensitivity - 0.0005, 0.0005, 0.01)
		changed = true
	}
	if rend.UI_Button(ui, "settings_sens_up", {x + 74, y + 280, 44, 30}, "+", false) {
		settings.mouseSensitivity = clamp(settings.mouseSensitivity + 0.0005, 0.0005, 0.01)
		changed = true
	}

	rend.UI_Label(ui, {x + 176, y + 144}, "BACKDROP", 1.45, ui.theme.textMuted)
	if rend.UI_Button(ui, "settings_theme", {x + 176, y + 166, 142, 30}, Editor_Settings_Clear_Label(settings.clearTheme), false) {
		switch settings.clearTheme {
		case .DEEP:     settings.clearTheme = .GRAPHITE
		case .GRAPHITE: settings.clearTheme = .DAWN
		case .DAWN:     settings.clearTheme = .DEEP
		}
		rend.Renderer_Set_Clear_Color(r, Editor_Settings_Clear_Color(settings))
		changed = true
	}

	if rend.UI_Button(ui, "settings_reset", {x + 176, y + 280, 142, 30}, "RESET", false) {
		settings^ = Editor_Settings_Default()
		eng.Set_Debug_Show_Grid(settings.showGrid)
		eng.Window_Set_VSync(win, settings.vsync)
		rend.Renderer_Set_Clear_Color(r, Editor_Settings_Clear_Color(settings))
		changed = true
	}

	if changed {
		if Editor_Settings_Save(settings) {
			if notifySave do rend.Notification_Tray_Push(notifications, "SETTINGS SAVED", .SUCCESS)
		} else {
			rend.Notification_Tray_Push(notifications, "SETTINGS SAVE FAILED", .ERROR, 3.0)
		}
	}
}
