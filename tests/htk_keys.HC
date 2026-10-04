#include "lib/htk/htk.hc"

I64 failures;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

Bool Parse(U8 *text, I64 *key, I64 *mods)
{
  CStrs value;

  StrsInitS(&value, text);
  return HtkWindowKeyParse(&value, key, mods);
}

U0 TestSettingsKeys()
{
  I64 key, mods;
  U8 *text, *name;
  CTermEvent e;

  HtkWindowKeysDefault;
  Check(Parse("alt + f7", &key, &mods) && key == TERM_KEY_F7 &&
    mods == TERM_MOD_ALT, "parse function-key binding with case and spaces");
  Check(Parse("Ctrl+Alt+m", &key, &mods) && key == 'm' &&
    mods == (TERM_MOD_CTRL | TERM_MOD_ALT), "parse combined modifiers");
  Check(Parse("None", &key, &mods) && !key && !mods, "parse disabled binding");
  Check(!Parse("Alt+", &key, &mods) && !Parse("Alt+Alt+m", &key, &mods) &&
    !Parse("Super+m", &key, &mods) && !Parse("Alt+F13", &key, &mods) &&
    !Parse("", &key, &mods), "reject malformed bindings");
  name = HtkWindowKeyName('+', TERM_MOD_CTRL);
  Check(Parse(name, &key, &mods) && key == '+' && mods == TERM_MOD_CTRL,
    "literal plus roundtrips through named key");
  Free(name);
  MemSet(&e, 0, sizeof(CTermEvent));
  e.key = TERM_KEY_F7;
  e.mods = TERM_MOD_ALT | TERM_MOD_CTRL;
  Check(!HtkWindowKeyMatches(&e, htk_move_key, htk_move_mods),
    "shortcuts require exact modifiers");
  e.mods = TERM_MOD_ALT;
  Check(HtkWindowKeyMatches(&e, htk_move_key, htk_move_mods),
    "default shortcut matches its modifiers");

  Check(HtkSettingsLoadText("[htk]\nmove_key = Alt+m\nresize_key = Alt+r\n") &&
    htk_move_key == 'm' && htk_resize_key == 'r' &&
    htk_move_mods == TERM_MOD_ALT && htk_resize_mods == TERM_MOD_ALT,
    "INI configures both activation shortcuts");
  text = HtkSettingsText;
  HtkWindowKeysDefault;
  Check(HtkSettingsLoadText(text) && htk_move_key == 'm' && htk_resize_key == 'r',
    "settings serialization preserves keybindings on reload");
  Free(text);
  Check(HtkSettingsLoadText("[htk]\nmove_key = broken\nresize_key = None\n") &&
    htk_move_key == 'm' && !htk_resize_key,
    "invalid config retains binding while None disables the other");
  Check(!HtkSettingsLoadText("[htk]\nmove_key = Alt+x\n[broken\n") &&
    htk_move_key == 'm', "malformed INI cannot partially change bindings");
  HtkWindowKeysDefault;
  Check(HtkSettingsLoadText("[htk]\nmove_key = Alt+F8\nresize_key = Alt+F7\n") &&
    htk_move_key == TERM_KEY_F8 && htk_resize_key == TERM_KEY_F7,
    "INI can swap the current shortcuts atomically");
  Check(HtkSettingsLoadText("[htk]\nmove_key = Alt+x\nresize_key = Alt+x\n") &&
    htk_move_key == TERM_KEY_F8 && htk_resize_key == TERM_KEY_F7,
    "conflicting INI shortcuts leave the current pair intact");
  Check(HtkSettingsLoadText("[htk]\ntheme = 1\n") &&
    htk_move_key == TERM_KEY_F8 && htk_resize_key == TERM_KEY_F7,
    "older settings files preserve unspecified keybindings");
  HtkWindowKeysDefault;
}

U0 TestSettingsDialog()
{
  HtkSettingsOpen;
  Check(!StrCmp(htk_set_move->text, "Alt+F7") &&
    !StrCmp(htk_set_resize->text, "Alt+F8"), "Settings shows default shortcuts");
  HtkSetText(htk_set_move, "Alt+x");
  HtkSetText(htk_set_resize, "Alt+y");
  Check(HtkSettingsApply(NULL) && htk_move_key == 'x' && htk_resize_key == 'y',
    "Settings applies custom shortcuts");
  HtkSetText(htk_set_move, "Alt+z");
  HtkSetText(htk_set_resize, "Alt+z");
  Check(!HtkSettingsApply(NULL) && htk_move_key == 'x' && htk_resize_key == 'y',
    "Settings rejects conflicting shortcuts before applying");
  HtkWindowKeysDefault;
  HtkSettingsSync;
  Check(!StrCmp(htk_set_move->text, "Alt+F7") &&
    !StrCmp(htk_set_resize->text, "Alt+F8"), "Settings refresh restores defaults");
  HtkSettingsClose(NULL);
}

// Exercise the actual desktop settings parser without accessing ~/htk.ini.
term_width = 100;
term_height = 40;
HtkThemeDefault;
TestSettingsKeys;
TestSettingsDialog;
"htk keys: %d failures\n", failures;
Exit(failures != 0);
