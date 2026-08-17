// Color picker dialog, adjusted to the terminal: 16 swatches on a basic
// terminal, the 256-color palette on a 256-color one, and the palette plus
// R/G/B sliders when true color is available. HtkColorPick returns the
// chosen 0xRRGGBB or -1 when cancelled.

I64 htk_pick_rgb;      // current choice
Bool htk_pick_ok;
HtkCtl *htk_pick_win, *htk_pick_preview, *htk_pick_hex;
HtkCtl *htk_pick_r, *htk_pick_g, *htk_pick_b;

U0 HtkPickShow()
{
  U8 hex[16];

  if (htk_pick_r) {
    htk_pick_r->value = htk_pick_rgb >> 16 & 0xFF;
    htk_pick_g->value = htk_pick_rgb >> 8 & 0xFF;
    htk_pick_b->value = htk_pick_rgb & 0xFF;
  }
  StrPrint(hex, "#%06X", htk_pick_rgb);
  HtkSetText(htk_pick_hex, hex);
  htk_dirty = TRUE;
}

// Palette canvas: row 0 the 16 basic colors (2 cells each), then the
// 6x6x6 cube as 6 rows of 36 and a row of 24 grays; on a 16-color terminal
// only the first row exists.
I64 HtkPickCellColor(I64 x, I64 y)
{
  if (y == 0) {
    if (x / 2 < 16)
      return x / 2;
    return -1;
  }
  if (y <= 6 && x < 36)
    return TermColor256(16 + (y - 1) * 36 + x);
  if (y == 7 && x < 24)
    return TermColor256(232 + x);
  return -1;
}

U0 HtkPickPalettePaint(HtkCtl *c)
{
  I64 x, y, color, rows = 1;

  if (TermColorDepth > 16)
    rows = 8;
  for (y = 0; y < rows; y++)
    for (x = 0; x < 36; x++) {
      color = HtkPickCellColor(x, y);
      if (color >= 0)
        HtkChr(c->x + x, c->y + y, ' ', TERM_WHITE, color);
    }
}

U0 HtkPickPaletteHit(HtkCtl *c)
{
  I64 color = HtkPickCellColor(c->mouse_x, c->mouse_y);

  if (c->mouse_pressed && color >= 0) {
    htk_pick_rgb = TermColorToRgb(color);
    HtkPickShow;
  }
}

U0 HtkPickPreviewPaint(HtkCtl *c)
{
  I64 color = TermColorRgb(htk_pick_rgb >> 16 & 0xFF, htk_pick_rgb >> 8 & 0xFF,
    htk_pick_rgb & 0xFF);

  if (TermColorDepth <= 16)
    color = TermRgbToBasic(htk_pick_rgb);
  HtkRect(c->x, c->y, c->w, c->h, ' ', TERM_WHITE, color);
}

U0 HtkPickSlide(HtkCtl *slider)
{
  htk_pick_rgb = htk_pick_r->value << 16 | htk_pick_g->value << 8 |
    htk_pick_b->value;
  HtkPickShow;
}

U0 HtkPickOk(HtkCtl *b)
{
  htk_pick_ok = TRUE;
  HtkWindowClose(htk_pick_win);
}

U0 HtkPickCancel(HtkCtl *b)
{
  HtkWindowClose(htk_pick_win);
}

HtkCtl *HtkPickSlider(HtkCtl *box, U8 *name, I64 value)
{
  HtkCtl *row = HtkNew(HTK_BOX);
  HtkCtl *label = HtkNew(HTK_LABEL);
  HtkCtl *slider = HtkSliderNew(0, 255);

  HtkSetText(label, name);
  slider->value = value;
  slider->changed = &HtkPickSlide;
  HtkAdd(row, label);
  HtkAdd(row, slider);
  HtkAdd(box, row);
  return slider;
}

I64 HtkColorPick(U8 *title, I64 rgb=0x808080)
{
  HtkCtl *box = HtkNew(HTK_BOX);
  HtkCtl *palette, *row, *ok, *cancel;
  I64 rows = 1;

  box->vertical = TRUE;
  htk_pick_rgb = rgb & 0xFFFFFF;
  htk_pick_ok = FALSE;
  htk_pick_r = NULL;
  if (TermColorDepth > 16)
    rows = 8;
  palette = HtkCanvasNew(36, rows, &HtkPickPalettePaint, 0);
  palette->changed = &HtkPickPaletteHit;
  HtkAdd(box, palette);
  if (TermColorDepth > 256) {
    htk_pick_r = HtkPickSlider(box, "R", rgb >> 16 & 0xFF);
    htk_pick_g = HtkPickSlider(box, "G", rgb >> 8 & 0xFF);
    htk_pick_b = HtkPickSlider(box, "B", rgb & 0xFF);
  }
  row = HtkNew(HTK_BOX);
  htk_pick_preview = HtkCanvasNew(8, 1, &HtkPickPreviewPaint, 0);
  HtkAdd(row, htk_pick_preview);
  htk_pick_hex = HtkNew(HTK_LABEL);
  HtkAdd(row, htk_pick_hex);
  HtkAdd(box, row);
  row = HtkNew(HTK_BOX);
  ok = HtkButtonNew("  OK  ");
  ok->changed = &HtkPickOk;
  HtkAdd(row, ok);
  cancel = HtkButtonNew(" Cancel ");
  cancel->changed = &HtkPickCancel;
  HtkAdd(row, cancel);
  HtkAdd(box, row);
  HtkPickShow;
  htk_pick_win = HtkDialogNew(title, box);
  htk_pick_win->link = ok;  // Enter accepts
  HtkModal(htk_pick_win);
  htk_pick_r = NULL;
  if (htk_pick_ok)
    return htk_pick_rgb;
  return -1;
}
