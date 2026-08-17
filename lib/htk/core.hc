// htk core: the control tree, the Turbo Vision palette, and clipped
// drawing over lib/term cells.  Every widget is one HtkCtl; behavior lives
// in per-widget files and is dispatched by kind in loop.hc.

#define HTK_WINDOW    0
#define HTK_BOX       1
#define HTK_GRID      2
#define HTK_LABEL     3
#define HTK_BUTTON    4
#define HTK_ENTRY     5
#define HTK_CHECKBOX  6
#define HTK_SLIDER    7
#define HTK_PROGRESS  8
#define HTK_SEP       9
#define HTK_CANVAS    10
#define HTK_MENU      11
#define HTK_MENUITEM  12
#define HTK_COMBO     13
#define HTK_RADIO     14
#define HTK_SPIN      15
#define HTK_MULTILINE 16
#define HTK_GROUP     17
#define HTK_TAB       18
#define HTK_TABPAGE   19
#define HTK_TOOLBAR   20
#define HTK_STATUS    21
#define HTK_SPLIT     22
#define HTK_SCROLL    23
#define HTK_TABLE     24
#define HTK_TREE      25
#define HTK_TREENODE  26
#define HTK_ITEM      27
#define HTK_POPUP     28

// The theme: every color the widgets use, changeable at runtime.  The
// defaults are the Borland palette; assign any htk_theme field (then touch
// htk_dirty) to restyle, or call HtkThemeDefault to reset.
class HtkTheme
{
  I64 desk_fg, desk_bg;   // desktop pattern
  I64 bg, fg;             // window body
  I64 dim;                // disabled text, inactive frames
  I64 frame;              // active window border
  I64 title;              // window title text
  I64 btn_bg, btn_fg;     // buttons
  I64 focus_bg;           // focused widget highlight
  I64 field_bg, field_fg; // entry/combo/spin fields
  I64 sel_bg, sel_fg;     // menu/list selection
  I64 accent;
};

HtkTheme htk_theme;

U0 HtkThemeDefault()
{
  htk_theme.desk_fg = TERM_CYAN;
  htk_theme.desk_bg = TERM_BLUE;
  htk_theme.bg = TERM_WHITE;
  htk_theme.fg = TERM_BLACK;
  htk_theme.dim = TERM_GRAY;
  htk_theme.frame = TERM_BRIGHT_WHITE;
  htk_theme.title = TERM_BLACK;
  htk_theme.btn_bg = TERM_GREEN;
  htk_theme.btn_fg = TERM_BLACK;
  htk_theme.focus_bg = TERM_CYAN;
  htk_theme.field_bg = TERM_BLUE;
  htk_theme.field_fg = TERM_BRIGHT_WHITE;
  htk_theme.sel_bg = TERM_GREEN;
  htk_theme.sel_fg = TERM_BRIGHT_WHITE;
  htk_theme.accent = TERM_BRIGHT_YELLOW;
}

#define HTK_C_DESK_FG  htk_theme.desk_fg
#define HTK_C_DESK_BG  htk_theme.desk_bg
#define HTK_C_BG       htk_theme.bg
#define HTK_C_FG       htk_theme.fg
#define HTK_C_DIM      htk_theme.dim
#define HTK_C_FRAME    htk_theme.frame
#define HTK_C_TITLE    htk_theme.title
#define HTK_C_BTN_BG   htk_theme.btn_bg
#define HTK_C_BTN_FG   htk_theme.btn_fg
#define HTK_C_FOCUS_BG htk_theme.focus_bg
#define HTK_C_FIELD_BG htk_theme.field_bg
#define HTK_C_FIELD_FG htk_theme.field_fg
#define HTK_C_SEL_BG   htk_theme.sel_bg
#define HTK_C_SEL_FG   htk_theme.sel_fg
#define HTK_C_ACCENT   htk_theme.accent

// Box-drawing runes.
#define HTK_R_H  0x2500
#define HTK_R_V  0x2502
#define HTK_R_TL 0x250C
#define HTK_R_TR 0x2510
#define HTK_R_BL 0x2514
#define HTK_R_BR 0x2518
#define HTK_R_DH 0x2550
#define HTK_R_DV 0x2551
#define HTK_R_DTL 0x2554
#define HTK_R_DTR 0x2557
#define HTK_R_DBL 0x255A
#define HTK_R_DBR 0x255D
#define HTK_R_BLOCK 0x2588
#define HTK_R_LIGHT 0x2591
#define HTK_R_MED   0x2592
#define HTK_R_DOT   0x2022
#define HTK_R_DOWN  0x25BC
#define HTK_R_RIGHT 0x25B8
#define HTK_R_OPEN  0x25BE
#define HTK_R_CLOSE 0x25A0

class HtkCtl
{
  I64 kind;
  HtkCtl *parent;
  HtkCtl *kids;
  HtkCtl *sib;
  HtkCtl *link;       // popup owner, tree selection, tabpage payload
  I64 x, y, w, h;    // laid-out rect, absolute cells
  I64 pw, ph;        // preferred size from measure
  U8 *text;
  I64 value;         // state: checked, position, selection, tab index
  I64 low, high;     // bounds; table: high = row count; window: low=dismissable
  I64 top;           // first visible row / scroll offset
  I64 cursor;        // entry/multiline cursor, byte index
  I64 col, row;      // grid placement
  I64 fn, data;      // canvas draw callback / table cell callback + data
  I64 mouse_x, mouse_y, mouse_button;
  Bool mouse_pressed, mouse_motion;
  I64 user;          // adapter's UiCtl
  U0 (*changed)(HtkCtl *c);
  U0 (*submit)(HtkCtl *c);   // entry: Enter pressed
  Bool vertical;
  Bool expand;
  Bool focusable;
  Bool disabled;
  Bool hidden;
  Bool secret;       // password entry
  Bool readonly;     // entry/multiline: navigation only
  Bool closed;       // window dismissed
};

// Deferred call: due timestamp, repeating interval (0 = one shot).
class HtkHook
{
  HtkHook *next;
  I64 due, ms;
  I64 fn, a, b;      // fn(a, b)
};

HtkCtl *htk_windows;   // bottom to top, chained via sib
HtkCtl *htk_focus;
HtkCtl *htk_popup;
HtkCtl *htk_drag;
I64 htk_drag_dx, htk_drag_dy;
Bool htk_drag_resize;
HtkHook *htk_hooks;
Bool htk_dirty;
Bool htk_running;
Bool htk_started;
I64 htk_clip_x, htk_clip_y, htk_clip_x2, htk_clip_y2;

// Cross-file dispatch, defined in loop.hc.
U0 HtkMeasureCtl(HtkCtl *c);
U0 HtkLayoutCtl(HtkCtl *c);
U0 HtkDrawCtl(HtkCtl *c);
Bool HtkKeyCtl(HtkCtl *c, CTermEvent *e);
U0 HtkSetFocus(HtkCtl *c);
U0 HtkPopupOpen(HtkCtl *popup);
U0 HtkPopupClose();
U0 HtkWindowClose(HtkCtl *w);

HtkCtl *HtkNew(I64 kind)
{
  HtkCtl *c = CAlloc(sizeof(HtkCtl));

  c->kind = kind;
  c->text = StrNew("");
  return c;
}

U0 HtkAdd(HtkCtl *parent, HtkCtl *kid)
{
  HtkCtl *k = parent->kids;

  kid->parent = parent;
  kid->sib = NULL;
  if (!k) {
    parent->kids = kid;
    return;
  }
  while (k->sib)
    k = k->sib;
  k->sib = kid;
}

U0 HtkSetText(HtkCtl *c, U8 *text)
{
  Free(c->text);
  c->text = StrNew(text);
  htk_dirty = TRUE;
}

U0 HtkFire(HtkCtl *c)
{
  U0 (*hit)(HtkCtl *c) = c->changed;

  htk_dirty = TRUE;
  if (hit)
    hit(c);
}

HtkCtl *HtkTop()
{
  HtkCtl *w = htk_windows;

  if (!w)
    return NULL;
  while (w->sib)
    w = w->sib;
  return w;
}

I64 HtkKidCount(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 n = 0;

  while (k) {
    n++;
    k = k->sib;
  }
  return n;
}

HtkCtl *HtkKidAt(HtkCtl *c, I64 index)
{
  HtkCtl *k = c->kids;

  while (k && index > 0) {
    k = k->sib;
    index--;
  }
  return k;
}

// Display width in runes, up to the first newline terminator.
I64 HtkRunes(U8 *text)
{
  I64 i = 0, n = 0;

  if (!text)
    return 0;
  while (text[i] && text[i] != '\n') {
    TermRuneNext(text, &i);
    n++;
  }
  return n;
}

// Narrow the clip: the request intersects whatever is already in force,
// so nested widgets can never paint outside their container.
U0 HtkClipSet(I64 x, I64 y, I64 w, I64 h)
{
  if (x > htk_clip_x)
    htk_clip_x = x;
  if (y > htk_clip_y)
    htk_clip_y = y;
  if (x + w < htk_clip_x2)
    htk_clip_x2 = x + w;
  if (y + h < htk_clip_y2)
    htk_clip_y2 = y + h;
}

// Reset (widen) the clip to the whole screen; only this widens it.
U0 HtkClipAll()
{
  htk_clip_x = 0;
  htk_clip_y = 0;
  htk_clip_x2 = TermWidth;
  htk_clip_y2 = TermHeight;
}

U0 HtkChr(I64 x, I64 y, I64 rune, I64 fg, I64 bg, I64 attr=0)
{
  if (x >= htk_clip_x && y >= htk_clip_y && x < htk_clip_x2 && y < htk_clip_y2)
    TermCell(x, y, rune, fg, bg, attr);
}

U0 HtkStr(I64 x, I64 y, U8 *text, I64 fg, I64 bg, I64 attr=0)
{
  I64 i = 0;

  if (!text)
    return;
  while (text[i] && text[i] != '\n') {
    HtkChr(x, y, TermRuneNext(text, &i), fg, bg, attr);
    x++;
  }
}

U0 HtkRect(I64 x, I64 y, I64 w, I64 h, I64 rune, I64 fg, I64 bg, I64 attr=0)
{
  I64 i, j;

  for (j = y; j < y + h; j++)
    for (i = x; i < x + w; i++)
      HtkChr(i, j, rune, fg, bg, attr);
}

U0 HtkFrame(I64 x, I64 y, I64 w, I64 h, Bool dbl, I64 fg, I64 bg)
{
  I64 i;
  I64 rh = HTK_R_H, rv = HTK_R_V;
  I64 tl = HTK_R_TL, tr = HTK_R_TR, bl = HTK_R_BL, br = HTK_R_BR;

  if (dbl) {
    rh = HTK_R_DH;
    rv = HTK_R_DV;
    tl = HTK_R_DTL;
    tr = HTK_R_DTR;
    bl = HTK_R_DBL;
    br = HTK_R_DBR;
  }
  for (i = x + 1; i < x + w - 1; i++) {
    HtkChr(i, y, rh, fg, bg);
    HtkChr(i, y + h - 1, rh, fg, bg);
  }
  for (i = y + 1; i < y + h - 1; i++) {
    HtkChr(x, i, rv, fg, bg);
    HtkChr(x + w - 1, i, rv, fg, bg);
  }
  HtkChr(x, y, tl, fg, bg);
  HtkChr(x + w - 1, y, tr, fg, bg);
  HtkChr(x, y + h - 1, bl, fg, bg);
  HtkChr(x + w - 1, y + h - 1, br, fg, bg);
}

// Turbo Vision shadow: keep the runes underneath, repaint them dark.
U0 HtkShade(I64 x, I64 y, I64 w, I64 h)
{
  I64 i, j;
  U64 cell;

  for (j = y; j < y + h; j++)
    for (i = x; i < x + w; i++)
      if (i >= 0 && j >= 0 && i < TermWidth && j < TermHeight) {
        cell = TermPeek(i, j);
        TermCell(i, j, cell & 0xFFFFFFFF, TERM_GRAY, TERM_BLACK);
      }
}

Bool HtkFocused(HtkCtl *c)
{
  return htk_focus == c;
}

// Text colors honoring the disabled state.
I64 HtkInk(HtkCtl *c, I64 normal)
{
  if (c->disabled)
    return HTK_C_DIM;
  return normal;
}
