// Checkbox "[x]", switch, and the vertical radio group "( )/(•)"; radio
// options are HTK_ITEM kids and value is the selected index.

HtkCtl *HtkCheckboxNew(U8 *text, Bool checked)
{
  HtkCtl *c = HtkNew(HTK_CHECKBOX);

  HtkSetText(c, text);
  c->value = checked;
  c->focusable = TRUE;
  return c;
}

U0 HtkCheckboxMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 4;
  c->ph = 1;
}

U0 HtkCheckboxDraw(HtkCtl *c)
{
  I64 bg = HtkBg(c, HTK_C_BG);
  U8 *mark = "[ ]";
  if (c->value)
    mark = "[x]";
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FG, bg);
  HtkStr(c->x, c->y, mark, HtkInk(c, HTK_C_FG), bg);
  HtkStr(c->x + 4, c->y, c->text, HtkInk(c, HTK_C_FG), bg);
}

Bool HtkCheckboxKey(HtkCtl *c, CTermEvent *e)
{
  if (e->key == ' ' || e->key == TERM_KEY_ENTER) {
    c->value = !c->value;
    HtkFire(c);
    return TRUE;
  }
  return FALSE;
}

// Switch: a compact binary control, with an optional label.  It deliberately
// shares the checkbox's Bool value and changed hook, but has a distinct
// presentation for settings-style UIs.
HtkCtl *HtkSwitchNew(U8 *text="", Bool on=FALSE)
{
  HtkCtl *c = HtkNew(HTK_SWITCH);

  HtkSetText(c, text);
  c->value = on;
  c->focusable = TRUE;
  return c;
}

U0 HtkSwitchMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 8;  // "[ OFF ]" plus one separating cell
  c->ph = 1;
}

U0 HtkSwitchDraw(HtkCtl *c)
{
  I64 bg = HtkBg(c, HTK_C_BG);
  I64 switch_bg = bg;
  I64 switch_fg = HtkInk(c, HTK_C_DIM);
  U8 *state = "[ OFF ]";

  if (c->value) {
    state = "[ ON  ]";
    switch_bg = HtkBg(c, HTK_C_BTN_BG);
    switch_fg = HtkInk(c, HTK_C_BTN_FG);
  }
  HtkRect(c->x, c->y, c->w, 1, ' ', HtkInk(c, HTK_C_FG), bg);
  HtkStr(c->x, c->y, state, switch_fg, switch_bg);
  HtkStr(c->x + 8, c->y, c->text, HtkInk(c, HTK_C_FG), bg);
}

U0 HtkSwitchSet(HtkCtl *c, Bool on)
{
  on = !!on;
  if (c->value == on)
    return;
  c->value = on;
  HtkFire(c);
}

Bool HtkSwitchKey(HtkCtl *c, CTermEvent *e)
{
  if (e->key == ' ' || e->key == TERM_KEY_ENTER) {
    HtkSwitchSet(c, !c->value);
    return TRUE;
  }
  return FALSE;
}

// Activity spinner.  It starts when attached to a window and stops re-arming
// itself when that window closes or the control is hidden.
U0 HtkSpinnerTick(I64 ctl, I64 unused)
{
  HtkCtl *c = ctl;
  HtkCtl *w = HtkOwnerWindow(c);

  if (!w || w->closed || c->hidden)
    return;
  c->value = (c->value + 1) & 3;
  htk_dirty = TRUE;
  HtkHookAdd(125, 0, &HtkSpinnerTick, c, 0);
}

HtkCtl *HtkSpinnerNew(U8 *text="")
{
  HtkCtl *c = HtkNew(HTK_SPINNER);

  HtkSetText(c, text);
  HtkHookAdd(125, 0, &HtkSpinnerTick, c, 0);
  return c;
}

U0 HtkSpinnerMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 2;  // frame plus a separating cell
  c->ph = 1;
}

U0 HtkSpinnerDraw(HtkCtl *c)
{
  I64 rune = '|';
  I64 bg = HtkBg(c, HTK_C_BG);

  if (c->value == 1)
    rune = '/';
  else if (c->value == 2)
    rune = '-';
  else if (c->value == 3)
    rune = '\\';
  HtkRect(c->x, c->y, c->w, 1, ' ', HtkInk(c, HTK_C_FG), bg);
  HtkChr(c->x, c->y, rune, HtkInk(c, HTK_C_ACCENT), bg, TERM_BOLD);
  HtkStr(c->x + 2, c->y, c->text, HtkInk(c, HTK_C_FG), bg);
}

HtkCtl *HtkRadioNew()
{
  HtkCtl *c = HtkNew(HTK_RADIO);

  c->focusable = TRUE;
  c->value = -1;
  return c;
}

#define HtkRadioAdd HtkAddItem

U0 HtkRadioMeasure(HtkCtl *c)
{
  c->pw = HtkItemsWidth(c);
  c->ph = HtkKidCount(c);
}

U0 HtkRadioDraw(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 i = 0, bg;

  while (k && i < c->h) {
    bg = HTK_C_BG;
    if (i == c->value)
      bg = HtkBg(c, bg);
    HtkRect(c->x, c->y + i, c->w, 1, ' ', HTK_C_FG, bg);
    HtkStr(c->x, c->y + i, "( )", HtkInk(c, HTK_C_FG), bg);
    if (i == c->value)
      HtkChr(c->x + 1, c->y + i, HTK_R_DOT, HtkInk(c, HTK_C_FG), bg);
    HtkStr(c->x + 4, c->y + i, k->text, HtkInk(c, HTK_C_FG), bg);
    k = k->sib;
    i++;
  }
}

Bool HtkRadioKey(HtkCtl *c, CTermEvent *e)
{
  I64 count = HtkKidCount(c);

  if (!count)
    return FALSE;
  if (e->key == TERM_KEY_UP && c->value > 0)
    c->value--;
  else if (e->key == TERM_KEY_DOWN && c->value < count - 1)
    c->value++;
  else
    return FALSE;
  HtkFire(c);
  return TRUE;
}
