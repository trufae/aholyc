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

U0 TextKey(HtkCtl *c, I64 key, I64 mods=0)
{
  CTermEvent e;

  e.key = key; e.mods = mods;
  HtkMultilineKey(c, &e);
}

U0 TestVim()
{
  HtkCtl *window = HtkWindowNew("Vim", 40, 12);
  HtkCtl *c = HtkMultilineNew("é😀 end\nsecond\nlast");
  HtkCtl *other;

  HtkAdd(window, c);
  HtkVimSet(TRUE);
  Check(c->vim_mode && !c->vim_insert, "global Vim mode updates existing textareas");
  other = HtkMultilineNew("");
  Check(other->vim_mode, "new textareas inherit Vim setting");
  TextKey(c, 'l');
  Check(c->cursor == 2, "Vim moves by UTF-8 runes");
  TextKey(c, 'j');
  Check(c->cursor == 12, "Vim vertical motion retains rune column");
  TextKey(c, 'g'); TextKey(c, 'g'); TextKey(c, 'w');
  Check(c->cursor == 7, "Vim word motion skips whitespace");
  TextKey(c, 'b'); TextKey(c, 'x');
  Check(!StrCmp(c->text, "😀 end\nsecond\nlast"), "Vim x deletes one UTF-8 rune");
  TextKey(c, 'u');
  Check(!StrCmp(c->text, "é😀 end\nsecond\nlast"), "generic textarea Vim undo");
  TextKey(c, 'r', TERM_MOD_CTRL); TextKey(c, 'u');
  Check(!StrCmp(c->text, "é😀 end\nsecond\nlast"), "generic textarea Vim redo");
  TextKey(c, 'i'); TextKey(c, 'A'); TextKey(c, 'B'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!c->vim_insert && !StrCmp(c->text, "ABé😀 end\nsecond\nlast"), "Vim insert mode and escape");
  TextKey(c, 'u');
  Check(!StrCmp(c->text, "é😀 end\nsecond\nlast"), "Vim insert history groups typing");
  TextKey(c, 'y'); TextKey(c, 'y'); TextKey(c, 'p');
  Check(!StrCmp(c->text, "é😀 end\né😀 end\nsecond\nlast"), "Vim yy and linewise paste");
  TextKey(c, 'u'); TextKey(c, 'G'); TextKey(c, 'd'); TextKey(c, 'd');
  Check(!StrCmp(c->text, "é😀 end\nsecond"), "Vim dd removes final unterminated line");
  TextKey(c, 'u'); TextKey(c, 'O'); TextKey(c, 'X'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "é😀 end\nsecond\nX\nlast"), "Vim opens line above");
  TextKey(c, 'u'); TextKey(c, 'u'); TextKey(c, 'o'); TextKey(c, 'Y'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "é😀 end\nsecond\nlast\nY"), "Vim opens line below");
  TextKey(c, 'u'); TextKey(c, 'u'); TextKey(c, 'g'); TextKey(c, 'g');
  TextKey(c, 'c'); TextKey(c, 'w'); TextKey(c, 'Z'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "Zend\nsecond\nlast"), "Vim changes a word");
  HtkSetText(c, "readonly"); c->cursor = 0; c->anchor = -1; c->readonly = TRUE;
  TextKey(c, 'x'); TextKey(c, 'd'); TextKey(c, 'd'); TextKey(c, 'p');
  TextKey(c, 'i'); TextKey(c, 'Q'); TextKey(c, 'u');
  Check(!StrCmp(c->text, "readonly") && !c->vim_insert, "readonly Vim prevents every edit");
  c->readonly = FALSE;
  HtkVimSet(FALSE);
  TextKey(c, 'z');
  Check(!StrCmp(c->text, "zreadonly"), "disabling Vim restores ordinary typing");
  HtkVimMode(other, TRUE); TextKey(other, 'i'); TextKey(other, 0xE9);
  Check(!StrCmp(other->text, "é"), "individual detached textarea can enable Vim");
  HtkDestroy(other); HtkWindowClose(window); HtkDestroy(window);
}

U0 TestThemes()
{
  HtkCtl *window = HtkWindowNew("Palette", 50, 10), *menu, *bar, *button;
  U8 *saved;
  I64 i, x;

  TermBuffersAlloc;
  menu = HtkMenuNew(window, "File");
  HtkMenuItem(menu, "Open");
  bar = HtkToolbarNew; button = HtkToolButtonNew("¶");
  HtkAdd(bar, button); HtkAdd(window, bar);
  for (i = 0; i < HTK_THEME_COUNT; i++) {
    HtkThemePreset(i);
    HtkWindowLayout(window);
    HtkClipAll;
    HtkWindowDraw(window);
    Check(htk_theme.menu_bg != htk_theme.bg && htk_theme.tool_bg != htk_theme.bg &&
      htk_theme.menu_bg != htk_theme.tool_bg, "theme separates menubar, toolbar and body");
    Check(TermCellBg(term_back[(window->y + 1) * TermWidth + window->x + 1]) == htk_theme.menu_bg &&
      TermCellBg(term_back[bar->y * TermWidth + bar->x + bar->w - 1]) == htk_theme.tool_bg,
      "menubar and toolbar draw their theme backgrounds");
  }
  HtkThemePreset(5);
  for (x = 0; x < TermWidth * TermHeight; x++) term_back[x] = 0;
  HtkClipAll;
  HtkWindowDraw(window);
  for (x = 0; x < TermWidth * TermHeight; x++)
    Check(TermCellChar(term_back[x]) < 128, "Serial theme emits ASCII cells");
  Check(htk_theme.fg < 8 && htk_theme.menu_bg < 8 && htk_theme.tool_bg < 8,
    "Serial uses basic ANSI colors");
  HtkVimSet(TRUE);
  saved = HtkSettingsText;
  HtkThemePreset(0); HtkVimSet(FALSE);
  Check(HtkSettingsLoadText(saved) && htk_desk_theme == 5 && htk_theme.ascii && htk_vim_mode,
    "theme and Vim mode survive settings serialization");
  Free(saved);
  Check(!HtkSettingsLoadText("[htk]\nvim_mode = 0\n[broken\n") && htk_vim_mode,
    "invalid settings do not change Vim mode");
  HtkVimSet(FALSE); HtkThemePreset(0);
  HtkWindowClose(window); HtkDestroy(window);
  Free(term_back); Free(term_front);
}

U0 TestMenus()
{
  HtkCtl *window = HtkWindowNew("Keyboard menus", 40, 10);
  HtkCtl *menu = HtkMenuNew(window, "File");
  CTermEvent e;

  HtkMenuItem(menu, "New");
  e.key = 'm'; e.mods = TERM_MOD_ALT;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == menu, "Alt-M opens window menubar");
  HtkPopupClose;
  e.key = TERM_KEY_F10; e.mods = 0;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == menu, "F10 opens window menubar");
  HtkPopupClose;
  e.key = 'a'; e.mods = TERM_MOD_ALT;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == htk_app_menu, "Alt-A opens desktop App menu");
  HtkPopupClose;
  e.key = TERM_KEY_F10;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == htk_app_menu, "Alt-F10 opens desktop App menu");
  HtkPopupClose;
  HtkWindowClose(window); HtkDestroy(window);
}

// Exercise the actual desktop settings parser without accessing ~/htk.ini.
term_width = 100;
term_height = 40;
HtkThemeDefault;
TestSettingsKeys;
TestSettingsDialog;
TestVim;
TestThemes;
TestMenus;
"htk keys: %d failures\n", failures;
Exit(failures != 0);
