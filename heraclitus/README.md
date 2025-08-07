# Fix Soon:
- Better render pass state tracking... maybe push and pop GL state procs? Since we are caching them we'll be able to check those calls and not do em if not necessary
- Bring sun shadow maps up to the same quality as point shadow maps
- Split shadow-casting point lights and non-shadow-casting lights... this can just be a bool... but should be separate arrays in the global frame uniform
- AABB's!!!


# Complete:
- Frames in flight sync, triple buffered persistently mapped buffers
- Immediate vertex rendering system
- Text rendering
- Point light shadow mapping
- Full blinn-phong shading model
- Menu (press ESC)
- Zoom (scroll wheel)
- GLTF model loading (works as far as I can tell, obviously not even close to all the features)
