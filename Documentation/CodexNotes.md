# Codex Notes

Small, durable notes for future coding sessions. Keep this file curated: record recurring gotchas, architectural decisions, and fixes that explain how this repo wants to be changed. Do not turn it into a full changelog.

## How To Use

- Read this file before making non-trivial changes.
- Add an entry when a fix teaches a reusable lesson about the engine.
- Keep entries short: symptom, cause, solution, and files touched.
- Prefer stable patterns over one-off implementation details.

## Scale Gizmo Plane Handles

Symptom: scale mode only supported single-axis handles and a uniform center cube, while translate mode had useful in-between plane handles.

Cause: scale drag logic only mapped handles to X, Y, Z, or uniform scale.

Solution: add scale `XY`, `XZ`, and `YZ` handles that reuse the screen-space scale drag direction and apply the same factor to two scale components. Draw and hit-test the scale plane squares similarly to translate planes, colored by the excluded normal axis.

Files touched: `scene/gizmo.odin`, `renderer/renderer.odin`.

## Scale Gizmo Center Clarity

Symptom: the scale tool's center white cube visually competed with the axis and plane handles.

Cause: the center cube was large and fully opaque.

Solution: reduce `GIZMO_SCALE_CENTER_SIZE` and draw the center cube through `Renderer_Draw_Mesh_Alpha` with temporary blending enabled.

Files touched: `scene/gizmo.odin`, `renderer/renderer.odin`.

## Cone Mesh Winding

Symptom: the cone rendered inside out when back-face culling was enabled.

Cause: generated cone triangles had reversed winding even though the normals pointed outward.

Solution: flip cone side triangles from `apex, p0, p1` to `apex, p1, p0`, and flip base triangles from `center, p1, p0` to `center, p0, p1`.

Files touched: `renderer/mesh.odin`.
