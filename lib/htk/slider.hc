// Value widgets: slider, progress bar, and spinner.

HtkCtl *HtkSliderNew(I64 low, I64 high)
{
  HtkCtl *c = HtkNew(HTK_SLIDER);

  c->low = low;
  c->high = high;
  c->value = low;
  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

U0 HtkSliderMeasure(HtkCtl *c)
{
  c->pw = 12;
  c->ph = 1;
}

I64 HtkSliderThumb(HtkCtl *c)
{
  I64 span = c->high - c->low;

  if (span < 1)
    span = 1;
  return (c->value - c->low) * (c->w - 1) / span;
}

U0 HtkSliderDraw(HtkCtl *c)
{
  I64 i;
  I64 fg = HtkInk(c, HTK_C_DIM);

  for (i = 0; i < c->w; i++)
    HtkChr(c->x + i, c->y, HTK_R_H, fg, HTK_C_BG);
  HtkChr(c->x + HtkSliderThumb(c), c->y, HTK_R_BLOCK,
    HtkInk(c, HTK_C_FIELD_BG), HTK_C_BG);
  if (HtkFocused(c))
    HtkChr(c->x + HtkSliderThumb(c), c->y, HTK_R_BLOCK, HTK_C_FOCUS_BG, HTK_C_BG);
}

U0 HtkSliderSet(HtkCtl *c, I64 value)
{
  if (value < c->low)
    value = c->low;
  if (value > c->high)
    value = c->high;
  if (value == c->value)
    return;
  c->value = value;
  HtkFire(c);
}

Bool HtkSliderKey(HtkCtl *c, CTermEvent *e)
{
  I64 step = (c->high - c->low) / 20;

  if (step < 1)
    step = 1;
  if (e->key == TERM_KEY_LEFT)
    HtkSliderSet(c, c->value - step);
  else if (e->key == TERM_KEY_RIGHT)
    HtkSliderSet(c, c->value + step);
  else if (e->key == TERM_KEY_HOME)
    HtkSliderSet(c, c->low);
  else if (e->key == TERM_KEY_END)
    HtkSliderSet(c, c->high);
  else
    return FALSE;
  return TRUE;
}

U0 HtkSliderMouse(HtkCtl *c, I64 x)
{
  I64 span = c->w - 1;

  if (span < 1)
    span = 1;
  HtkSliderSet(c, c->low + (x - c->x) * (c->high - c->low) / span);
}

HtkCtl *HtkProgressNew()
{
  HtkCtl *c = HtkNew(HTK_PROGRESS);

  c->high = 100;
  c->expand = TRUE;
  return c;
}

U0 HtkProgressDraw(HtkCtl *c)
{
  I64 fill = c->value * c->w / 100;
  I64 i;

  if (fill < 0)
    fill = 0;
  if (fill > c->w)
    fill = c->w;
  for (i = 0; i < c->w; i++) {
    if (i < fill)
      HtkChr(c->x + i, c->y, HTK_R_BLOCK, HTK_C_FIELD_BG, HTK_C_BG);
    else
      HtkChr(c->x + i, c->y, HTK_R_LIGHT, HTK_C_DIM, HTK_C_BG);
  }
}

HtkCtl *HtkSpinNew(I64 low, I64 high)
{
  HtkCtl *c = HtkNew(HTK_SPIN);

  c->low = low;
  c->high = high;
  c->value = low;
  c->focusable = TRUE;
  return c;
}

U0 HtkSpinMeasure(HtkCtl *c)
{
  c->pw = 10;
  c->ph = 1;
}

U0 HtkSpinDraw(HtkCtl *c)
{
  U8 num[24];
  I64 bg = HTK_C_FIELD_BG;

  if (HtkFocused(c))
    bg = HTK_C_FOCUS_BG;
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FIELD_FG, bg);
  HtkChr(c->x, c->y, 0x25C4, HtkInk(c, HTK_C_FIELD_FG), bg);
  HtkChr(c->x + c->w - 1, c->y, 0x25BA, HtkInk(c, HTK_C_FIELD_FG), bg);
  StrPrint(num, "%d", c->value);
  HtkStr(c->x + (c->w - StrLen(num)) / 2, c->y, num,
    HtkInk(c, HTK_C_FIELD_FG), bg);
}

Bool HtkSpinKey(HtkCtl *c, CTermEvent *e)
{
  I64 was = c->value;

  if (e->key == TERM_KEY_UP || e->key == TERM_KEY_RIGHT)
    c->value++;
  else if (e->key == TERM_KEY_DOWN || e->key == TERM_KEY_LEFT)
    c->value--;
  else
    return FALSE;
  if (c->value < c->low)
    c->value = c->low;
  if (c->value > c->high)
    c->value = c->high;
  if (c->value != was)
    HtkFire(c);
  return TRUE;
}
