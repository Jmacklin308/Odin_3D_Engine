# UI System

The UI is an immediate-mode overlay in `renderer/ui.odin`. Build it fresh every frame between `UI_Begin` and `UI_End`, then draw it after the 3D scene with `UI_Render`.

## Setup

```odin
ui: rend.UI_Context
rend.UI_Init(&ui)
defer rend.UI_Shutdown(&ui)
```

## Per Frame

```odin
screenSize := eng.Vec2{f32(win.width), f32(win.height)}

rend.UI_Begin(&ui, &r, screenSize, inp, dt)

rend.UI_Panel(&ui, {14, 14, 292, 120})
rend.UI_Label(&ui, {30, 30}, "TOOLS", 2.0)

if rend.UI_Button(&ui, "move_tool", {30, 64, 80, 32}, "MOVE", moveSelected) {
	// handle click
}

rend.UI_End(&ui)

uiCaptured := rend.UI_Wants_Mouse(&ui)

// Draw after scene rendering has queued its work.
rend.UI_Render(&ui)
```

## Widgets

- `UI_Panel(ctx, rect)` draws a panel with shadow and accent bar.
- `UI_Rect_Fill(ctx, rect, color)` draws a flat screen-space rectangle.
- `UI_Label(ctx, pos, text, scale, color)` draws debug-font text.
- `UI_Button(ctx, id, rect, text, selected)` returns `true` on click.
- `UI_Model_Preview(ctx, rect, mesh, angle, color)` draws a small 3D mesh preview.
- `UI_Hover_Amount(ctx, id)` returns animated hover amount from `0..1`.
- `UI_Time(ctx)` returns UI elapsed time for simple animation.
- `UI_Wants_Mouse(ctx)` tells scene input to ignore mouse clicks when UI is hot/active.

## Notes

- Coordinates are pixels from the top-left of the window.
- `UI_Rect` is `{x, y, w, h}`.
- Button `id` strings must be stable and unique per widget.
- The UI only captures left mouse button interactions right now.
- Queue UI commands before `Renderer_End`; render with `UI_Render` after scene/gizmo/grid draws.
