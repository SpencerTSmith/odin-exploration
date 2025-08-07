# Fix Soon:
- Better render pass state tracking... maybe push and pop GL state procs? Since we are caching them we'll be able to check those calls and not do em if not necessary

# Complete:
- Frames in flight sync, triple buffered persistently mapped buffers
- Immediate vertex rendering system
- Text rendering
- Point light shadow mapping
- Full blinn-phong shading model
- Menu (press ESC)
- Zoom (scroll wheel)
