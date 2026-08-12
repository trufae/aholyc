// Cell canvas: the draw callback paints through HtkCanvas* helpers using
// F64 cell coordinates, so callers can scale from any coordinate space.

HtkCtl *htk_canvas;    // canvas being painted, during its callback only
I64 htk_canvas_fg;

HtkCtl *HtkCanvasNew(I64 w, I64 h, I64 drawfn, I64 data)
{
  HtkCtl *c = HtkNew(HTK_CANVAS);

  c->pw = w;
  c->ph = h;
  c->fn = drawfn;
  c->data = data;
  return c;
}

U0 HtkCanvasMeasure(HtkCtl *c)
{
  // pw/ph fixed at creation.
}

U0 HtkCanvasDraw(HtkCtl *c)
{
  I64 paint = c->fn;
  I64 ox = htk_clip_x, oy = htk_clip_y, ox2 = htk_clip_x2, oy2 = htk_clip_y2;

  HtkRect(c->x, c->y, c->w, c->h, ' ', TERM_WHITE, TERM_BLACK);
  if (!paint)
    return;
  HtkClipSet(c->x, c->y, c->w, c->h);
  htk_canvas = c;
  htk_canvas_fg = TERM_WHITE;
  paint(c);
  htk_canvas = NULL;
  htk_clip_x = ox;
  htk_clip_y = oy;
  htk_clip_x2 = ox2;
  htk_clip_y2 = oy2;
}

// Map 0.0..1.0 RGB onto the 16-color palette: threshold each channel and
// add the bright bit for vivid inputs.
U0 HtkCanvasColor(F64 r, F64 g, F64 b)
{
  I64 index = 0;

  if (r > 0.25)
    index |= 1;
  if (g > 0.25)
    index |= 2;
  if (b > 0.25)
    index |= 4;
  // ANSI order is R=1 G=2 B=4 remapped: red,green,yellow,blue...
  I64 map[8];
  map[0] = TERM_BLACK;
  map[1] = TERM_RED;
  map[2] = TERM_GREEN;
  map[3] = TERM_YELLOW;
  map[4] = TERM_BLUE;
  map[5] = TERM_MAGENTA;
  map[6] = TERM_CYAN;
  map[7] = TERM_WHITE;
  index = map[index];
  if (index && (r > 0.7 || g > 0.7 || b > 0.7))
    index |= 8;
  htk_canvas_fg = index;
}

U0 HtkCanvasRect(F64 x, F64 y, F64 w, F64 h)
{
  HtkCtl *c = htk_canvas;

  if (!c)
    return;
  HtkRect(c->x + ToI64(x), c->y + ToI64(y), ToI64(w), ToI64(h), ' ',
    TERM_WHITE, htk_canvas_fg);
}

U0 HtkCanvasLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  HtkCtl *c = htk_canvas;
  I64 ax, ay, bx, by, dx, dy, sx, sy, err, twice;

  if (!c)
    return;
  ax = ToI64(x1);
  ay = ToI64(y1);
  bx = ToI64(x2);
  by = ToI64(y2);
  dx = bx - ax;
  if (dx < 0)
    dx = -dx;
  dy = by - ay;
  if (dy < 0)
    dy = -dy;
  sx = -1;
  if (ax < bx)
    sx = 1;
  sy = -1;
  if (ay < by)
    sy = 1;
  err = dx - dy;
  while (TRUE) {
    HtkChr(c->x + ax, c->y + ay, HTK_R_BLOCK, htk_canvas_fg, TERM_BLACK);
    if (ax == bx && ay == by)
      break;
    twice = err * 2;
    if (twice > -dy) {
      err -= dy;
      ax += sx;
    }
    if (twice < dx) {
      err += dx;
      ay += sy;
    }
  }
}
