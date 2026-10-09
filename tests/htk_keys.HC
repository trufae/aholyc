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
  Check(htk_set_shadow->value == htk_window_shadow, "Settings shows window shadow preference");
  htk_set_shadow->value = FALSE; HtkSettingsShadow(htk_set_shadow);
  Check(!htk_window_shadow, "window shadow toggle applies immediately");
  U8 *saved = HtkSettingsText;
  htk_window_shadow = TRUE;
  Check(HtkSettingsLoadText(saved) && !htk_window_shadow, "window shadow setting survives serialization");
  Free(saved);
  Check(HtkSettingsLoadText("[htk]\nwindow_shadow = 2\n") && !htk_window_shadow,
    "invalid shadow setting is ignored");
  htk_window_shadow = TRUE; HtkSettingsSync;
  HtkSettingsClose(NULL);
}

U0 TestEnvironment()
{
  U8 *name = "AHOLYC_HTK_ENV_TEST", *previous = EnvGet(name), *value, *snapshot;
  CStrBuf long_value;
  I64 i;

  StrBufInit(&long_value);
  for (i = 0; i < 600; i++) StrBufPutC(&long_value, 'a' + i % 26);
  Check(EnvSet(name, long_value.a), "environment setter returns native success");
  value = EnvGet(name);
  Check(value && !StrCmp(value, long_value.a), "environment getter returns a complete long string");
  snapshot = value;
  Check(EnvSet(name, "changed"), "environment setter replaces the value");
  value = EnvGet(name);
  Check(value && !StrCmp(value, "changed") && snapshot && !StrCmp(snapshot, long_value.a),
    "environment strings are owned copies independent of later changes");
  Free(value); Free(snapshot);
  Check(EnvSet(name), "environment setter deletes the variable");
  value = EnvGet(name);
  Check(!value && !EnvSet("", "bad") && !EnvGet(""), "environment getter handles missing and invalid names");
  Free(value); EnvSet(name, previous); Free(previous); StrBufFini(&long_value);
}

#ifdef UI_HTK_VIMODE
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
  TextKey(c, 'g'); TextKey(c, 'g'); TextKey(c, 'W');
  Check(c->cursor == 7, "Vim word motion skips whitespace");
  TextKey(c, 'B'); TextKey(c, 'x');
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
  TextKey(c, 'u'); TextKey(c, 'o'); TextKey(c, 'Y'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "é😀 end\nsecond\nlast\nY"), "Vim opens line below");
  TextKey(c, 'u'); TextKey(c, 'g'); TextKey(c, 'g');
  TextKey(c, 'c'); TextKey(c, 'w'); TextKey(c, 'Z'); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "Z😀 end\nsecond\nlast"), "Vim changes a word without eating spaces or symbols");
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
  TextKey(other, TERM_KEY_LEFT); TextKey(other, TERM_KEY_RIGHT); TextKey(other, 'x');
  TextKey(other, TERM_KEY_ESCAPE); TextKey(other, 'u');
  Check(!StrCmp(other->text, "é"), "ordinary navigation ends a Vim typing undo group");
  HtkDestroy(other); HtkWindowClose(window); HtkDestroy(window);
}

U0 TextKeys(HtkCtl *c, U8 *keys)
{
  I64 rune, n;

  while (*keys) {
    n = Utf8DecodeRune(keys, StrLen(keys), &rune);
    if (rune == 27) rune = TERM_KEY_ESCAPE;
    else if (rune == '\n') rune = TERM_KEY_ENTER;
    TextKey(c, rune); keys += n;
  }
}

U0 VimReset(HtkCtl *c, U8 *text)
{
  HtkSetText(c, text);
  c->cursor = 0; c->anchor = -1; c->readonly = FALSE;
  c->vim_insert = FALSE; c->vim_pending = 0; c->vim_vertical = FALSE; c->vim_at = 0;
  c->vim_visual = 0;
}

U0 TestVimVisual()
{
  HtkCtl *c = HtkMultilineNew("");
  CStrs clipboard;

  HtkVimMode(c, TRUE);
  VimReset(c, "one\né😀 two\nlast"); c->cursor = 6;
  TextKey(c, 'V');
  Check(c->vim_visual == 2 && c->anchor == 4 && c->cursor == 15 && c->vim_head == 6,
    "V selects entire UTF-8 source line, including newline");
  TextKey(c, 'j');
  Check(c->anchor == 4 && c->cursor == 19 && c->vim_head == 16,
    "Visual line motion selects final unterminated line and keeps display column");
  TextKeys(c, "kk");
  Check(c->anchor == 15 && c->cursor == 0 && c->vim_head == 1,
    "Visual line selection reverses without moving caret to exclusive endpoint");
  TextKey(c, 'y'); HtkClipboardGet(&clipboard);
  Check(!c->vim_visual && c->cursor == 0 && c->anchor == -1 &&
    StrsLen(&clipboard) == 15 && !MemCmp(clipboard.a, "one\né😀 two\n", 15) && htk_clipboard_lines,
    "Visual line yank returns to Normal and keeps a linewise clipboard");

  c->cursor = 6; TextKey(c, 'v');
  Check(c->anchor == 6 && c->cursor == 10, "v includes a complete multibyte character");
  TextKey(c, 'l'); TextKeys(c, "hh");
  Check(c->anchor == 10 && c->cursor == 4 && c->vim_head == 4,
    "Visual character motions extend and reverse across UTF-8 boundaries");
  TextKey(c, 'y'); HtkClipboardGet(&clipboard);
  Check(StrsLen(&clipboard) == 6 && !MemCmp(clipboard.a, "é😀", 6) && !htk_clipboard_lines,
    "Visual character yank copies inclusive selection");
  TextKeys(c, "Vv"); TextKey(c, TERM_KEY_ESCAPE);
  Check(!c->vim_visual && c->cursor == 4 && c->anchor == -1,
    "switching Visual kinds and Escape preserve logical caret");

  c->cursor = 16; TextKeys(c, "Vd");
  Check(!StrCmp(c->text, "one\né😀 two") && !c->vim_visual && c->cursor == 4,
    "Visual delete of last unterminated line removes its preceding separator");
  HtkClipboardGet(&clipboard);
  Check(StrsLen(&clipboard) == 5 && !MemCmp(clipboard.a, "last\n", 5),
    "unterminated line yank appends a newline for linewise paste");
  TextKey(c, 'u'); Check(!StrCmp(c->text, "one\né😀 two\nlast"), "Visual delete is one undo step");

  c->cursor = 6; TextKeys(c, "Vcnewé"); TextKey(c, TERM_KEY_ESCAPE);
  Check(!StrCmp(c->text, "one\nnewé\nlast") && !c->vim_insert && !c->vim_visual,
    "Visual line change leaves one editable line");
  TextKey(c, 'u');
  Check(!StrCmp(c->text, "one\né😀 two\nlast"), "Visual change and Insert text undo together");

  c->cursor = 6; c->readonly = TRUE; TextKeys(c, "Vdcxp");
  Check(c->vim_visual == 2 && !c->vim_insert && !StrCmp(c->text, "one\né😀 two\nlast"),
    "readonly Visual selections reject edits and keep selection");
  TextKey(c, 'y'); Check(!c->vim_visual, "readonly Visual yank remains available");
  c->readonly = FALSE; c->cursor = 6; TextKeys(c, "Vj");
  HtkVimMode(c, FALSE);
  Check(!c->vim_visual && c->cursor == 16 && c->anchor == -1,
    "disabling Vim collapses Visual selection to logical caret");

  HtkVimMode(c, TRUE); VimReset(c, "one\n"); c->cursor = 4; TextKeys(c, "Vy");
  HtkClipboardGet(&clipboard);
  Check(StrsLen(&clipboard) == 1 && clipboard.a[0] == '\n', "empty final Visual line yanks a blank line");
  TextKey(c, 'p'); Check(!StrCmp(c->text, "one\n\n"), "blank line yank can be pasted");
  VimReset(c, "abc"); TextKeys(c, "vly"); c->cursor = 2; TextKeys(c, "vp");
  Check(!StrCmp(c->text, "abab") && !c->vim_visual, "Visual paste replaces selection with saved clipboard");
  HtkDestroy(c);
}

// Text and cursor expectations were checked against Vim 9.2 with default
// joinspaces, no indentation, and separate input/undo boundaries.
U0 VimCase(HtkCtl *c, U8 *text, U8 *keys, U8 *expected, I64 cursor, U8 *name)
{
  VimReset(c, text); TextKeys(c, keys);
  Check(!StrCmp(c->text, expected) && c->cursor == cursor && !c->vim_insert, name);
}

U0 TestVimInteractions()
{
  HtkCtl *c = HtkMultilineNew("");

  HtkVimMode(c, TRUE);
  VimCase(c, "foo\n  bar", "J", "foo bar", 3, "J joins and strips indentation");
  TextKey(c, 'u'); Check(!StrCmp(c->text, "foo\n  bar"), "J is one undo step");
  TextKey(c, 'r', TERM_MOD_CTRL); Check(!StrCmp(c->text, "foo bar"), "redo line join");
  VimCase(c, "foo \n  bar", "J", "foo bar", 4, "J keeps existing trailing space");
  VimCase(c, "foo.\nbar", "J", "foo.  bar", 4, "J uses Vim sentence spacing");
  VimCase(c, "foo\n)", "J", "foo)", 3, "J avoids space before closing parenthesis");
  VimCase(c, "\n  bar", "J", "bar", 0, "J joins an empty first line");
  VimCase(c, "foo\n\nbar", "J", "foo\nbar", 2, "J joins an empty next line");
  VimCase(c, "foo", "J", "foo", 0, "J at EOF does nothing");
  VimCase(c, "é\n  😀", "J", "é 😀", 2, "J preserves UTF-8 boundaries");
  c->readonly = TRUE; TextKey(c, 'J');
  Check(!StrCmp(c->text, "é 😀"), "readonly Vim rejects J");
  VimCase(c, "one two", "cwX\x1b", "X two", 0, "cw preserves following whitespace");
  VimCase(c, "one,two", "cwX\x1b", "X,two", 0, "cw separates punctuation");
  VimCase(c, "one  two", "lllcwX\x1b", "oneXtwo", 3, "cw on whitespace changes just whitespace");
  VimCase(c, "one\ntwo", "dw", "\ntwo", 0, "dw at end of line preserves newline");
  VimCase(c, "\ntwo", "cwX\x1b", "X\ntwo", 0, "cw on empty line inserts without joining");
  VimCase(c, "one two", "cwnew word\x1bu", "one two", 0, "undo cw restores the whole change");
  TextKey(c, 'r', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "new word two"), "redo restores complete cw insertion");
  VimCase(c, "one\ntwo", "OX\x1bu", "one\ntwo", 0, "undo O restores line and typing together");
  VimCase(c, "one\ntwo", "oX\x1bu", "one\ntwo", 0, "undo o restores line and typing together");
  VimCase(c, "old", "ihello world\x1bu", "old", 0, "undo Insert includes spaces");
  VimCase(c, "old", "ihello\nworld\x1bu", "old", 0, "undo Insert includes line breaks");
  VimCase(c, "abc", "$", "abc", 2, "normal dollar stops on last character");
  TextKey(c, 'l'); TextKey(c, TERM_KEY_RIGHT);
  Check(c->cursor == 2, "normal right motion cannot pass the last character");
  TextKey(c, 'x');
  Check(!StrCmp(c->text, "ab") && c->cursor == 1, "x at EOL keeps cursor on the previous character");
  VimCase(c, "é😀", "$", "é😀", 2, "normal dollar stops at the final UTF-8 rune");
  VimCase(c, "  word", "IX\x1b", "  Xword", 2, "I inserts after indentation");
  VimCase(c, "one\n  two", "G", "one\n  two", 6, "G moves to first nonblank");
  VimCase(c, "one\n  two", "dd", "  two", 2, "dd moves to first nonblank");
  VimCase(c, "one\ntwo", "Gdd", "one", 0, "dd final line resets cursor naturally");
  VimCase(c, "one,two", "w", "one,two", 3, "w stops on punctuation");
  VimCase(c, "é😀 end", "w", "é😀 end", 2, "w separates letters from emoji");
  VimCase(c, "one\n\ntwo", "w", "one\n\ntwo", 4, "w stops at empty line");
  VimCase(c, "abc", "xlp", "bca", 2, "character paste places cursor on inserted character");
  VimCase(c, "abcd\nx\nabcd", "lljj", "abcd\nx\nabcd", 9, "vertical motion keeps column across short lines");
  VimCase(c, "abcd\nabcdef", "$j", "abcd\nabcdef", 10, "dollar keeps end-of-line position on vertical moves");
  VimCase(c, "é😀z\nabcd\né😀z", "ljj", "é😀z\nabcd\né😀z", 15,
    "vertical motion uses terminal columns for wide UTF-8");
  VimReset(c, "é😀z\nabcd"); TextKey(c, 'i');
  TextKey(c, TERM_KEY_RIGHT); TextKey(c, TERM_KEY_RIGHT);
  Check(c->cursor == 6, "Insert arrows move complete UTF-8 runes");
  TextKey(c, TERM_KEY_DOWN); Check(c->cursor == 11, "Insert down preserves display column");
  TextKey(c, TERM_KEY_UP); Check(c->cursor == 6, "Insert up returns to the same UTF-8 position");
  TextKey(c, TERM_KEY_END); Check(c->cursor == 7, "Insert End stays on current line");
  TextKey(c, TERM_KEY_HOME); Check(c->cursor == 0, "Insert Home stays on current line");
  TextKey(c, TERM_KEY_BACKSPACE); TextKey(c, 'X'); TextKey(c, TERM_KEY_BACKSPACE);
  TextKey(c, TERM_KEY_DELETE); TextKey(c, 'Q'); TextKey(c, TERM_KEY_ESCAPE); TextKey(c, 'u');
  Check(!StrCmp(c->text, "é😀z\nabcd"), "Insert undo combines typing and deletions");
  VimReset(c, "old"); TextKeys(c, "AX\x1bi"); TextKey(c, TERM_KEY_HOME);
  TextKey(c, TERM_KEY_BACKSPACE); TextKeys(c, "Q\x1bu");
  Check(!StrCmp(c->text, "oldX"), "a no-op Backspace does not merge across a navigation boundary");
  TextKey(c, 'u'); Check(!StrCmp(c->text, "old"), "previous Insert group stays independently undoable");
  HtkDestroy(c);
}

U0 TestVimControl()
{
  HtkCtl *c = HtkMultilineNew("");
  CStrBuf lines;
  CStrs clipboard;
  I64 i, revision;

  HtkVimMode(c, TRUE); c->h = 6;
  StrBufInit(&lines);
  for (i = 0; i < 12; i++) StrBufPutS(&lines, "é😀x\n");
  VimReset(c, lines.a); c->cursor = 2;
  TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->cursor == 34 && c->top == 4 && !c->vim_insert,
    "Ctrl-F pages viewport and UTF-8 caret with two overlapping rows");
  TextKey(c, 'b', TERM_MOD_CTRL);
  Check(c->cursor == 2 && c->top == 0, "Ctrl-B returns a page in Normal mode");
  TextKey(c, 'V'); TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->vim_visual == 2 && c->vim_head == 34 && c->anchor == 0 && c->cursor == 40,
    "Visual paging extends whole-line selection instead of cancelling it");
  TextKey(c, TERM_KEY_PGUP);
  Check(c->vim_visual == 2 && c->vim_head == 2 && c->cursor == 8,
    "PageUp shares Vim paging and preserves Visual selection");
  TextKey(c, TERM_KEY_ESCAPE); TextKey(c, 'i'); TextKey(c, 'e', TERM_MOD_CTRL);
  TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->vim_insert && c->cursor == 39 && c->top == 4,
    "Ctrl-F pages in Insert mode and keeps its insertion column");
  TextKey(c, 'b', TERM_MOD_CTRL);
  Check(c->vim_insert && c->cursor == 7 && !c->text_edit->undo,
    "Insert Ctrl-B pages without changing text or history");
  c->readonly = TRUE; TextKey(c, TERM_KEY_PGDN);
  Check(c->cursor == 39 && c->vim_insert, "readonly editors still page");
  c->h = 1; TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->cursor == 47, "single-row panes page by one line");
  for (i = 0; i < 20; i++) TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->cursor == StrLen(lines.a), "paging clamps at EOF");
  for (i = 0; i < 20; i++) TextKey(c, 'b', TERM_MOD_CTRL);
  Check(c->cursor == 7 && c->top == 0, "paging clamps at first line while retaining column");
  StrBufFini(&lines);

  VimReset(c, "abcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefgh");
  c->wrap = TRUE; c->w = 8; c->h = 6; c->top = 0; c->cursor = 1;
  TextKey(c, 'f', TERM_MOD_CTRL);
  Check(c->cursor == 33 && c->top == 4, "wrapped multiline paging uses display rows");
  TextKey(c, 'b', TERM_MOD_CTRL);
  Check(c->cursor == 1 && c->top == 0, "wrapped multiline paging keeps its display column");
  c->wrap = FALSE;

  VimReset(c, "é😀z\nabcd\né😀z"); TextKey(c, 'i');
  TextKey(c, 'e', TERM_MOD_CTRL); Check(c->cursor == 7, "Insert Ctrl-E reaches line end");
  TextKey(c, 'a', TERM_MOD_CTRL); Check(c->cursor == 0 && c->anchor < 0, "Insert Ctrl-A reaches line start");
  TextKey(c, TERM_KEY_RIGHT); TextKey(c, TERM_KEY_RIGHT);
  TextKey(c, 'n', TERM_MOD_CTRL); Check(c->cursor == 11, "Insert Ctrl-N keeps terminal column");
  TextKey(c, 'p', TERM_MOD_CTRL); Check(c->cursor == 6, "Insert Ctrl-P restores UTF-8 position");
  TextKey(c, 'd', TERM_MOD_CTRL); TextKey(c, 'h', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "é\nabcd\né😀z") && c->cursor == 2,
    "Ctrl-D/H delete complete UTF-8 characters");
  TextKey(c, 'z', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "é😀z\nabcd\né😀z"), "control deletions share the Insert undo group");

  VimReset(c, "alpha beta\nlast"); TextKey(c, 'i'); TextKey(c, 'e', TERM_MOD_CTRL);
  TextKey(c, 'u', TERM_MOD_CTRL); TextKey(c, 'k', TERM_MOD_CTRL);
  HtkClipboardGet(&clipboard);
  Check(!StrCmp(c->text, "last") && StrsLen(&clipboard) == 11 &&
    !MemCmp(clipboard.a, "alpha beta\n", 11), "consecutive line kills combine in the clipboard");
  TextKey(c, 'y', TERM_MOD_CTRL);
  Check(c->vim_insert && !StrCmp(c->text, "alpha beta\nlast"), "Insert Ctrl-Y yanks killed text");
  TextKey(c, 'z', TERM_MOD_CTRL); Check(!StrCmp(c->text, "last"), "yank is its own undo step");
  TextKey(c, 'z', TERM_MOD_CTRL); Check(!StrCmp(c->text, "\nlast"), "newline kill is independently undoable");
  TextKey(c, 'z', TERM_MOD_CTRL); Check(!StrCmp(c->text, "alpha beta\nlast"), "line kill undo");

  VimReset(c, "one two three"); TextKey(c, 'A');
  TextKey(c, 'w', TERM_MOD_CTRL); TextKey(c, 'w', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "one ") && !StrCmp(HtkClipboardText, "two three"),
    "consecutive backward word kills prepend in source order");
  TextKey(c, 'y', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "one two three"), "word kills can be yanked together");
  TextKey(c, 'a', TERM_MOD_CTRL); TextKey(c, 'k', TERM_MOD_CTRL);
  Check(!StrCmp(HtkClipboardText, "one two three"), "navigation starts a fresh kill sequence");

  VimReset(c, "é😀z\nnext"); TextKey(c, 'A'); TextKey(c, 't', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "éz😀\nnext") && c->cursor == 7, "Ctrl-T transposes full runes at line end");
  TextKey(c, 'z', TERM_MOD_CTRL); TextKey(c, 'a', TERM_MOD_CTRL);
  TextKey(c, 't', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "é😀z\nnext") && c->cursor == 0, "Ctrl-T at line start never joins lines");
  TextKey(c, TERM_KEY_RIGHT); TextKey(c, 't', TERM_MOD_CTRL);
  Check(!StrCmp(c->text, "😀éz\nnext") && c->cursor == 6, "Ctrl-T advances over transposed Unicode characters");
  revision = c->text_edit->revision; HtkClipboardSet("preserved"); c->readonly = TRUE;
  TextKey(c, 'k', TERM_MOD_CTRL); TextKey(c, 'u', TERM_MOD_CTRL); TextKey(c, 'w', TERM_MOD_CTRL);
  TextKey(c, 'd', TERM_MOD_CTRL); TextKey(c, 'h', TERM_MOD_CTRL);
  TextKey(c, 'y', TERM_MOD_CTRL); TextKey(c, 't', TERM_MOD_CTRL);
  Check(c->text_edit->revision == revision && !StrCmp(HtkClipboardText, "preserved"),
    "readonly control edits preserve text, history and clipboard");
  HtkDestroy(c);
}

#endif

U0 TestTextarea()
{
  HtkCtl *c = HtkMultilineNew("");
  CTermEvent e;

  e.mods = 0; e.key = 'V'; HtkMultilineKey(c, &e);
  e.key = 'J'; HtkMultilineKey(c, &e);
  e.key = 0xE9; HtkMultilineKey(c, &e);
  Check(!StrCmp(c->text, "VJé"), "ordinary textarea input works without enabling Vim");
  HtkDestroy(c);
}

U0 TestCursorShape()
{
  HtkCtl *window = HtkWindowNew("Cursor", 40, 12);
  HtkCtl *box = HtkNew(HTK_BOX), *editor = HtkMultilineNew("abc"), *entry = HtkEntryNew("command");

  box->vertical = TRUE; HtkAdd(box, editor); HtkAdd(box, entry); HtkAdd(window, box);
  TermBuffersAlloc; HtkWindowLayout(window); HtkSetFocus(editor); HtkClipAll;
  HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BAR, "ordinary textarea uses a vertical bar cursor");
  editor->cursor_shape = TERM_CURSOR_BLOCK; HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "textarea cursor shape can be chosen explicitly");
  editor->cursor_shape = TERM_CURSOR_BAR;
  #ifdef UI_HTK_VIMODE
  HtkVimMode(editor, TRUE); HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Vim Normal uses block cursor");
  TextKey(editor, 'i'); HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BAR && editor->cursor == 0 && !StrCmp(editor->text, "abc"),
    "Vim Insert uses bar without changing text or caret position");
  TextKey(editor, TERM_KEY_ESCAPE); TextKey(editor, 'V'); HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Vim Visual uses block cursor");
  HtkSetFocus(entry); HtkEntryDraw(entry);
  Check(term_cursor_shape == TERM_CURSOR_BAR, "entry focus replaces a Vim block with bar cursor");
  HtkSetFocus(editor); HtkVimMode(editor, FALSE); HtkMultilineDraw(editor);
  Check(term_cursor_shape == TERM_CURSOR_BAR, "disabling Vim returns to textarea cursor shape");
  #endif
  HtkWindowClose(window); HtkDestroy(window); Free(term_back); Free(term_front);
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
  HtkCtl *plain = HtkButtonNew("OK"), *status = HtkStatusbarNew(""), *mode = HtkToolButtonNew("Edit");
  plain->w = 8; plain->h = 1;
  status->x = 10; status->w = 12; status->h = 1;
  mode->x = 10; mode->w = 6; mode->h = 1;
  HtkAdd(status, mode);
  for (i = 0; i < 3; i++) {
    plain->disabled = i == 2; mode->disabled = i == 2;
    htk_focus = NULL; if (i == 1) htk_focus = plain;
    HtkClipAll; HtkButtonDraw(plain);
    Check(TermCellFg(term_back[3]) != TermCellBg(term_back[3]), "Serial plain button has readable contrast");
    if (i != 1) Check(TermCellFg(term_back[3]) == TERM_BLACK && TermCellBg(term_back[3]) == TERM_WHITE,
      "Serial white buttons use black text");
    htk_focus = NULL; if (i == 1) htk_focus = mode;
    HtkToolButtonDraw(mode);
    Check(TermCellFg(term_back[11]) != TermCellBg(term_back[11]), "Serial status button has readable contrast");
    mode->value = TRUE; HtkToolButtonDraw(mode);
    Check(TermCellFg(term_back[11]) == TERM_BLACK && TermCellBg(term_back[11]) == TERM_WHITE,
      "Serial selected buttons use black text on white");
    mode->value = FALSE;
  }
  htk_focus = NULL; HtkDestroy(plain); HtkDestroy(status);
  HtkCtl *popup, *disabled, *sub, *combo = HtkComboNew;
  disabled = HtkMenuItem(menu, "Disabled shortcut"); disabled->disabled = TRUE;
  sub = HtkSubMenu(menu, "Submenu"); HtkMenuItem(sub, "Nested item");
  popup = HtkPickNew(menu, 2, 2);
  for (i = 0; i < 3; i++) {
    popup->value = i; HtkClipAll; HtkPickDraw(popup);
    I64 selected = (popup->y + 1 + i) * TermWidth + popup->x + 2;
    Check(TermCellFg(term_back[selected]) == TERM_BLACK && TermCellBg(term_back[selected]) == TERM_WHITE,
      "Serial selected menu entries and disabled items use black on white");
    for (x = popup->x + 2; x < popup->x + popup->w - 1; x++) {
      selected = (popup->y + 1 + i) * TermWidth + x;
      Check(TermCellFg(term_back[selected]) != TermCellBg(term_back[selected]), "Serial menu text/shortcut contrast");
    }
    if (i == 2) {
      selected = (popup->y + 3) * TermWidth + popup->x + popup->w - 2;
      Check(TermCellChar(term_back[selected]) == '>' && TermCellFg(term_back[selected]) == TERM_BLACK,
        "Serial submenu marker is readable ASCII");
    }
  }
  HtkDestroy(popup);
  menu->disabled = TRUE; HtkMenubarDraw(window);
  x = (menu->y * TermWidth) + menu->x + 1;
  Check(TermCellFg(term_back[x]) == TERM_BLACK && TermCellBg(term_back[x]) == TERM_WHITE,
    "Serial disabled menu title remains readable");
  menu->disabled = FALSE;
  HtkComboAdd(combo, "Choice"); combo->value = 0;
  popup = HtkPickNew(combo, 2, 2); HtkClipAll; HtkPickDraw(popup);
  x = (popup->y + 1) * TermWidth + popup->x + 2;
  Check(TermCellFg(term_back[x]) == TERM_BLACK && TermCellBg(term_back[x]) == TERM_WHITE,
    "Serial combo dropdown uses the same readable selection colors");
  HtkDestroy(popup); HtkDestroy(combo);
  HtkCtl *toggle = HtkSwitchNew("Switch", TRUE), *slider = HtkSliderNew(0, 10), *progress = HtkProgressNew;
  toggle->w = 16; toggle->h = 1; toggle->disabled = TRUE;
  HtkClipAll; HtkSwitchDraw(toggle);
  Check(TermCellFg(term_back[2]) != TermCellBg(term_back[2]), "Serial disabled switch is readable");
  slider->w = 10; slider->h = 1; HtkSliderDraw(slider);
  Check(TermCellFg(term_back[0]) != TermCellBg(term_back[0]), "Serial slider thumb is visible");
  progress->w = 10; progress->h = 1; progress->value = 50; HtkProgressDraw(progress);
  Check(TermCellFg(term_back[0]) != TermCellBg(term_back[0]), "Serial progress fill is visible");
  HtkDestroy(toggle); HtkDestroy(slider); HtkDestroy(progress);
  HtkClipAll;
  HtkChr(0, 0, 0x1F600, TermColorRgb(100, 200, 255), TermColorRgb(20, 30, 50));
  Check(TermCellChar(term_back[0]) == '?' && TermCellFg(term_back[0]) < 8 &&
    TermCellBg(term_back[0]) < 8, "Serial degrades styled Unicode to ASCII and basic colors");
  #ifdef UI_HTK_VIMODE
  HtkVimSet(TRUE);
  #endif
  saved = HtkSettingsText;
  HtkThemePreset(0);
  #ifdef UI_HTK_VIMODE
  HtkVimSet(FALSE);
  Check(HtkSettingsLoadText(saved) && htk_desk_theme == 5 && htk_theme.ascii && htk_vim_mode,
    "theme and Vim mode survive settings serialization");
  #else
  Check(HtkSettingsLoadText(saved) && htk_desk_theme == 5 && htk_theme.ascii &&
    !MemMem(saved, StrLen(saved), "vim_mode", 8),
    "Vim-free build serializes themes without Vim settings");
  Check(HtkSettingsLoadText("[htk]\nvim_mode = 1\n"), "Vim-free build accepts shared settings files");
  #endif
  Free(saved);
  term_color_depth = 16777216;
  HtkThemePreset(4);
  Check(htk_theme.bg >= 512 && htk_theme.menu_bg >= 512 && htk_theme.tool_bg >= 512 &&
    htk_theme.menu_bg != htk_theme.tool_bg, "Modern has distinct truecolor surfaces");
  term_color_depth = 16;
  #ifdef UI_HTK_VIMODE
  Check(!HtkSettingsLoadText("[htk]\nvim_mode = 0\n[broken\n") && htk_vim_mode,
    "invalid settings do not change Vim mode");
  HtkVimSet(FALSE);
  #endif
  HtkThemePreset(0);
  HtkWindowClose(window); HtkDestroy(window);
  Free(term_back); Free(term_front);
}

U0 TestShadows()
{
  HtkCtl *window = HtkWindowNew("Shadow", 30, 8);
  I64 at;

  TermBuffersAlloc; window->x = 10; window->y = 5;
  at = (window->y + window->h) * TermWidth + window->x + 3;
  HtkClipAll; HtkRect(0, 0, TermWidth, TermHeight, 'x', TERM_YELLOW, TERM_GREEN);
  htk_window_shadow = TRUE; HtkWindowDraw(window);
  Check(TermCellChar(term_back[at]) == 'x' && TermCellFg(term_back[at]) == TERM_GRAY &&
    TermCellBg(term_back[at]) == TERM_BLACK, "enabled window shadow shades the desktop");
  HtkClipAll; HtkRect(0, 0, TermWidth, TermHeight, 'x', TERM_YELLOW, TERM_GREEN);
  htk_window_shadow = FALSE; HtkWindowDraw(window);
  Check(TermCellFg(term_back[at]) == TERM_YELLOW && TermCellBg(term_back[at]) == TERM_GREEN,
    "disabled window shadow leaves the desktop colors intact");
  htk_window_shadow = TRUE;
  HtkWindowClose(window); HtkDestroy(window); Free(term_back); Free(term_front);
}

U0 TestMenus()
{
  HtkCtl *window = HtkWindowNew("Keyboard menus", 40, 10);
  HtkCtl *menu = HtkMenuNew(window, "File");
  CTermEvent e;

  HtkMenuItem(menu, "New");
  HtkMenuSeparator(menu);
  HtkMenuItem(menu, "Save");
  e.key = 'm'; e.mods = TERM_MOD_ALT;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == menu, "Alt-M opens window menubar");
  HtkPopupClose;
  e.key = TERM_KEY_F10; e.mods = 0;
  HtkKey(&e);
  Check(htk_popup && HtkPopupRoot->link == menu, "F10 opens window menubar");
  e.key = TERM_KEY_DOWN; HtkKey(&e);
  Check(htk_popup->value == 2, "menu keyboard navigation skips separator downwards");
  e.key = TERM_KEY_UP; HtkKey(&e);
  Check(htk_popup->value == 0, "menu keyboard navigation skips separator upwards");
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
TestEnvironment;
TestTextarea;
TestCursorShape;
#ifdef UI_HTK_VIMODE
TestVim;
TestVimInteractions;
TestVimVisual;
TestVimControl;
#endif
TestThemes;
TestShadows;
TestMenus;
"htk keys: %d failures\n", failures;
Exit(failures != 0);
