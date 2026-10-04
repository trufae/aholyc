// Window-manager activation keys; exact modifiers keep ordinary keys free.
#include "../text/strs.hc"

I64 htk_move_key = TERM_KEY_F7, htk_move_mods = TERM_MOD_ALT;
I64 htk_resize_key = TERM_KEY_F8, htk_resize_mods = TERM_MOD_ALT;

#define HTK_KEY_NAMES 18
U8 *htk_key_names[HTK_KEY_NAMES] = {"SPACE", "TAB", "ENTER", "ESCAPE",
  "BACKSPACE", "UP", "DOWN", "LEFT", "RIGHT", "HOME", "END", "PAGEUP",
  "PAGEDOWN", "INSERT", "DELETE", "PLUS", "HASH", "SEMICOLON"};
I64 htk_key_codes[HTK_KEY_NAMES] = {' ', TERM_KEY_TAB, TERM_KEY_ENTER,
  TERM_KEY_ESCAPE, TERM_KEY_BACKSPACE, TERM_KEY_UP, TERM_KEY_DOWN,
  TERM_KEY_LEFT, TERM_KEY_RIGHT, TERM_KEY_HOME, TERM_KEY_END, TERM_KEY_PGUP,
  TERM_KEY_PGDN, TERM_KEY_INSERT, TERM_KEY_DELETE, '+', '#', ';'};

I64 HtkWindowKeyLower(I64 key)
{
  if (key >= 'A' && key <= 'Z')
    return key + 'a' - 'A';
  return key;
}

Bool HtkWindowSetKeybinding(I64 action, I64 key, I64 mods=0)
{
  I64 i;
  Bool valid = key == 0 || (key >= ' ' && key <= '~') ||
    (key >= TERM_KEY_F1 && key <= TERM_KEY_F12);

  if (mods & ~(TERM_MOD_SHIFT | TERM_MOD_ALT | TERM_MOD_CTRL))
    return FALSE;
  for (i = 0; i < HTK_KEY_NAMES; i++)
    if (key == htk_key_codes[i])
      valid = TRUE;
  if (!valid)
    return FALSE;
  key = HtkWindowKeyLower(key);
  if (!key)
    mods = 0;
  if (action == HTK_WM_MOVE) {
    if (key && key == htk_resize_key && mods == htk_resize_mods)
      return FALSE;
    htk_move_key = key;
    htk_move_mods = mods;
  } else if (action == HTK_WM_RESIZE) {
    if (key && key == htk_move_key && mods == htk_move_mods)
      return FALSE;
    htk_resize_key = key;
    htk_resize_mods = mods;
  } else
    return FALSE;
  return TRUE;
}

U0 HtkWindowKeysDefault()
{
  htk_move_key = TERM_KEY_F7;
  htk_resize_key = TERM_KEY_F8;
  htk_move_mods = TERM_MOD_ALT;
  htk_resize_mods = TERM_MOD_ALT;
}

// Apply a pair atomically, including a swap of the current shortcuts.
Bool HtkWindowSetKeys(I64 move_key, I64 move_mods, I64 resize_key, I64 resize_mods)
{
  I64 old_move = htk_move_key, old_move_mods = htk_move_mods;
  I64 old_resize = htk_resize_key, old_resize_mods = htk_resize_mods;

  HtkWindowSetKeybinding(HTK_WM_MOVE, 0);
  HtkWindowSetKeybinding(HTK_WM_RESIZE, 0);
  if (HtkWindowSetKeybinding(HTK_WM_MOVE, move_key, move_mods) &&
    HtkWindowSetKeybinding(HTK_WM_RESIZE, resize_key, resize_mods))
    return TRUE;
  htk_move_key = old_move;
  htk_move_mods = old_move_mods;
  htk_resize_key = old_resize;
  htk_resize_mods = old_resize_mods;
  return FALSE;
}

Bool HtkWindowKeyMatches(CTermEvent *e, I64 key, I64 mods)
{
  return key && HtkWindowKeyLower(e->key) == key && e->mods == mods;
}

// INI spelling: modifiers joined with '+', then a letter or named key.
// Invalid values leave the previous binding intact; None disables it.
Bool HtkWindowKeyParse(CStrs *text, I64 *key, I64 *mods)
{
  U8 name[64], *part = name, *next;
  I64 i, n = 0, c, flag, number = 0;

  for (i = 0; i < StrsLen(text); i++) {
    c = text->a[i];
    if (c != ' ' && c != '\t') {
      if (n >= sizeof(name) - 1)
        return FALSE;
      if (c >= 'a' && c <= 'z')
        c -= 'a' - 'A';
      name[n++] = c;
    }
  }
  name[n] = 0;
  *mods = 0;
  *key = 0;
  if (!StrCmp(name, "NONE"))
    return TRUE;
  next = MemChr(part, '+', StrLen(part));
  while (next) {
    *next = 0;
    flag = 0;
    if (!StrCmp(part, "CTRL"))
      flag = TERM_MOD_CTRL;
    else if (!StrCmp(part, "ALT"))
      flag = TERM_MOD_ALT;
    else if (!StrCmp(part, "SHIFT"))
      flag = TERM_MOD_SHIFT;
    if (!flag || *mods & flag)
      return FALSE;
    *mods |= flag;
    part = next + 1;
    next = MemChr(part, '+', StrLen(part));
  }
  if (StrLen(part) == 1 && *part >= '!' && *part <= '~')
    *key = HtkWindowKeyLower(*part);
  else {
    for (i = 0; i < HTK_KEY_NAMES; i++)
      if (!StrCmp(part, htk_key_names[i]))
        *key = htk_key_codes[i];
    if (!*key && *part == 'F') {
      for (i = 1; part[i]; i++) {
        if (i > 2 || part[i] < '0' || part[i] > '9')
          return FALSE;
        number = number * 10 + part[i] - '0';
      }
      if (number >= 1 && number <= 12)
        *key = TERM_KEY_F1 + number - 1;
    }
  }
  return *key != 0;
}

U8 *HtkWindowKeyName(I64 key, I64 mods)
{
  U8 name[16];
  U8 *ctrl = "", *alt = "", *shift = "";
  I64 i;

  if (!key)
    return StrNew("None");
  StrPrint(name, "%c", key);
  if (key >= TERM_KEY_F1 && key <= TERM_KEY_F12)
    StrPrint(name, "F%d", key - TERM_KEY_F1 + 1);
  else
    for (i = 0; i < HTK_KEY_NAMES; i++)
      if (key == htk_key_codes[i])
        StrCpy(name, htk_key_names[i]);
  if (mods & TERM_MOD_CTRL)
    ctrl = "Ctrl+";
  if (mods & TERM_MOD_ALT)
    alt = "Alt+";
  if (mods & TERM_MOD_SHIFT)
    shift = "Shift+";
  return MStrPrint("%s%s%s%s", ctrl, alt, shift, name);
}
