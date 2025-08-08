package main

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:math"

import stbtt "vendor:stb/truetype"
import gl "vendor:OpenGL"

FONT_DIR :: DATA_DIR + "fonts"

FONT_FIRST_CHAR :: 32
FONT_LAST_CHAR  :: 128
FONT_CHAR_COUNT :: FONT_LAST_CHAR - FONT_FIRST_CHAR

FONT_ATLAS_WIDTH  :: 512
FONT_ATLAS_HEIGHT :: 512

Font_Glyph :: struct {
  // Atlas bounding box
  x0: f32,
  y0: f32,
  x1: f32,
  y1: f32,

  x_off:   f32,
  y_off:   f32,
  advance: f32,
}

// NOTE: This is not integrated with the general asset system and deals with actual textures and such...
Font :: struct {
  pixel_height: f32,
  scale:        f32,

  ascent:   i32,
  descent:  i32,
  line_gap: i32,

  line_height: f32,

  glyphs: [FONT_CHAR_COUNT]Font_Glyph,
  atlas:  Texture,
}

Text_Alignment :: enum {
  LEFT,
  CENTER,
  RIGHT,
}

make_font :: proc(file_name: string, pixel_height: f32, allocator := context.allocator) -> (font: Font, ok: bool) {
  rel_path := filepath.join({FONT_DIR, file_name}, context.temp_allocator)

  font_data: []byte
  font_data, ok = os.read_entire_file(rel_path, context.temp_allocator)
  if !ok {
    log.error("Couldn't read font file: %s", rel_path)
    return font, ok
  }

  font.pixel_height = pixel_height

  // NOTE: Always loads only the first font
  font_info: stbtt.fontinfo
  ok = bool(stbtt.InitFont(&font_info, raw_data(font_data), stbtt.GetFontOffsetForIndex(raw_data(font_data), 0)))
  if !ok {
    log.error("STB Truetype could not init font file: %s", rel_path)
    return font, ok
  }

  stbtt.GetFontVMetrics(&font_info, &font.ascent, &font.descent, &font.line_gap)
  font.scale = stbtt.ScaleForPixelHeight(&font_info, pixel_height);

  font.line_height = font.scale * f32(font.ascent - font.descent + font.line_gap)

  bitmap := make([]byte, FONT_ATLAS_WIDTH * FONT_ATLAS_HEIGHT, allocator)
  defer delete(bitmap)

  packed_chars: [FONT_CHAR_COUNT]stbtt.packedchar
  pack_context: stbtt.pack_context
  stbtt.PackBegin(&pack_context, raw_data(bitmap), FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT, 0, 1, nil);
  stbtt.PackFontRange(&pack_context, raw_data(font_data), 0, pixel_height, FONT_FIRST_CHAR, FONT_CHAR_COUNT, &packed_chars[0])
  stbtt.PackEnd(&pack_context)

  for char, i in packed_chars {
    font.glyphs[i] = {
      x0 = f32(char.x0) / FONT_ATLAS_WIDTH,
      y0 = f32(char.y0) / FONT_ATLAS_HEIGHT,
      x1 = f32(char.x1) / FONT_ATLAS_WIDTH,
      y1 = f32(char.y1) / FONT_ATLAS_WIDTH,

      advance = char.xadvance,
      x_off   = char.xoff,
      y_off   = char.yoff,
    }
  }

  font.atlas = make_texture_from_data(._2D, .R8, .CLAMP_LINEAR, {raw_data(bitmap)}, FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT)

  // Make R show up as alpha
  swizzle := []i32{gl.ONE, gl.ONE, gl.ONE, gl.RED};
  gl.TextureParameteriv(font.atlas.id, gl.TEXTURE_SWIZZLE_RGBA, raw_data(swizzle))

  return font, ok
}

// FIXME: May wish to use the bounding box of each glyph
text_draw_rect :: proc(text: string, font: Font, x, y: f32,
                       align: Text_Alignment = .LEFT) -> (left, top, bottom, right: f32) {
  width, height := text_draw_size(text, font)
  left   = align_text_start_x(text, font, x, align)
  right  = left + width
  top    = y - (f32(font.ascent) * font.scale)
  bottom = top + height

  return left, top, bottom, right
}

text_draw_size :: proc(text: string, font: Font) -> (w, h: f32) {
  max_line_width: f32
  height := font.line_height

  line_width: f32
  for c, idx in text {
    if c == '\n' {
      // Don't count the last new-line
      if idx != len(text) - 1 {
        height += font.line_height
      }
      max_line_width = math.max(line_width, max_line_width)
      line_width = 0
      continue
    }

    glyph := font.glyphs[c - FONT_FIRST_CHAR]
    line_width += glyph.advance
  }

  max_line_width = math.max(line_width, max_line_width)

  return max_line_width, height
}

align_text_start_x :: proc(text: string, font: Font, x: f32, align: Text_Alignment) -> (x_start: f32) {
  switch align {
  case .LEFT:
    x_start = x
  case .CENTER:
    text_width := text_draw_width(text, font)
    x_start = x - (text_width * 0.5)
  case .RIGHT:
    text_width := text_draw_width(text, font)
    x_start = x - text_width
  }

  return x_start
}

text_draw_width :: proc(text: string, font: Font) -> f32 {
  w, _ := text_draw_size(text, font)
  return w
}

text_draw_height :: proc(text: string, font: Font) -> f32 {
  _, h := text_draw_size(text, font)
  return h
}

draw_text :: proc(text: string, font: Font, x, y: f32, rgba: vec4 = WHITE, align: Text_Alignment = .LEFT) {
  assert(font.atlas.id != 0, "Tried to use uninitialized font")

  x_start := align_text_start_x(text, font, x, align)

  x_cursor := x_start
  y_cursor := y

  for c in text {
    if c == '\n' {
      y_cursor += font.line_height
      x_cursor = x_start
      continue
    }

    glyph := font.glyphs[c - FONT_FIRST_CHAR]

    char_xy := vec2{x_cursor + glyph.x_off, y_cursor + glyph.y_off}
    char_w  := (glyph.x1 - glyph.x0) * FONT_ATLAS_WIDTH
    char_h  := (glyph.y1 - glyph.y0) * FONT_ATLAS_HEIGHT

    char_uv0 := vec2{glyph.x0, glyph.y0}
    char_uv1 := vec2{glyph.x1, glyph.y1}

    immediate_quad(char_xy, char_w, char_h, rgba, char_uv0, char_uv1, font.atlas)

    x_cursor += glyph.advance
  }
}

free_font :: proc(font: ^Font) {
  free_texture(&font.atlas)
}
