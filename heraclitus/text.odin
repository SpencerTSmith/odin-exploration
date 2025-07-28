package main

import "core:fmt"
import "core:os"
import "core:path/filepath"

import stbtt "vendor:stb/truetype"
import gl "vendor:OpenGL"

FONT_DIR :: "fonts"
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

Font :: struct {
  size:     f32,
  scale:    f32,
  ascent:   i32,
  descent:  i32,
  line_gap: i32,

  glyphs: [FONT_CHAR_COUNT]Font_Glyph,
  atlas:  Texture,
}

make_font :: proc(file_name: string, pixel_height: f32, allocater := context.allocator) -> (font: Font, ok: bool) {
  rel_path := filepath.join({FONT_DIR, file_name}, context.temp_allocator)

  font_data: []byte
  font_data, ok = os.read_entire_file(rel_path, context.temp_allocator)
  if !ok {
    fmt.eprintln("Couldn't read font file: %s", rel_path)
    return font, ok
  }

  // NOTE: Always loads only the first font
  font_info: stbtt.fontinfo
  ok = bool(stbtt.InitFont(&font_info, raw_data(font_data), stbtt.GetFontOffsetForIndex(raw_data(font_data), 0)))
  if !ok {
    fmt.eprintln("STB Truetype could not init font file: %s", rel_path)
    return font, ok
  }

  stbtt.GetFontVMetrics(&font_info, &font.ascent, &font.descent, &font.line_gap)
  font.scale = stbtt.ScaleForPixelHeight(&font_info, pixel_height);

  bitmap := make([]byte, FONT_ATLAS_WIDTH * FONT_ATLAS_HEIGHT, context.temp_allocator)

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

  font.atlas, ok = make_texture(bitmap, FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT, 1)

  return font, ok
}

draw_text :: proc(text: string, font: Font, x, y: f32) {
  // NOTE: Might not be amazing for performance to unset...
  immediate_set_texture(font.atlas)
  defer immediate_set_texture(state.immediate.white_texture)

  x_cursor := x
  for c in text {
    glyph := font.glyphs[c - FONT_FIRST_CHAR]

    char_xy := vec2{x_cursor + glyph.x_off, y + glyph.y_off}
    char_w  := (glyph.x1 - glyph.x0) * FONT_ATLAS_WIDTH
    char_h  := (glyph.y1 - glyph.y0) * FONT_ATLAS_HEIGHT

    char_uv0 := vec2{glyph.x0, glyph.y0}
    char_uv1 := vec2{glyph.x1, glyph.y1}

    immediate_quad(char_xy, char_w, char_h, char_uv0, char_uv1)

    x_cursor += glyph.advance
  }
}

free_font :: proc(font: ^Font) {
  free_texture(&font.atlas)
}
