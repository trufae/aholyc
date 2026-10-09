// Desktop layer: the [App] menu on the window bar (also the desktop's right
// click menu) with Refresh, Settings... and Quit, and the settings dialog
// that picks a color theme, the desktop color, whether the window bar is
// always shown, whether it carries a clock and whether unfocused windows
// are dimmed. Build with -DHTK_NODESK to leave all of this out.

#include "../io/file.hc"
#include "../inih/inih.hc"

extern I64 remove(U8 *path);

#define HTK_THEME_COUNT 7
U8 *htk_theme_names[HTK_THEME_COUNT] = {"Borland", "Dark", "Light", "Teal", "Modern", "Serial", "Light Borland"};

#define HTK_COLOR_COUNT 16
U8 *htk_color_names[HTK_COLOR_COUNT] = {"black", "red", "green", "yellow",
    "blue", "magenta", "cyan", "white", "gray", "bright red", "bright green",
  "bright yellow", "bright blue", "bright magenta", "bright cyan",
  "bright white"};

I64 htk_desk_theme;  // current preset index
Bool htk_settings_saved;
I64 htk_desk_custom = -1;  // desktop color chosen with Pick..., or -1
I64 htk_bar_custom = -1;   // window bar color chosen with Pick..., or -1
I64 htk_frame_custom = -1; // window border color chosen with Pick..., or -1

U0 HtkClockTick(I64 a, I64 b);

U0 HtkThemePreset(I64 index)
{
  HtkThemeDefault;
  htk_desk_theme = index;
  if (index == 1) {  // Dark
    htk_theme.desk_fg = TERM_GRAY;
    htk_theme.desk_bg = TERM_BLACK;
    htk_theme.bg = TERM_BLACK;
    htk_theme.fg = TERM_WHITE;
    htk_theme.dim = TERM_GRAY;
    htk_theme.frame = TERM_BRIGHT_CYAN;
    htk_theme.title = TERM_WHITE;
    htk_theme.btn_bg = TERM_BLUE;
    htk_theme.btn_fg = TERM_BRIGHT_WHITE;
    htk_theme.focus_bg = TERM_MAGENTA;
    htk_theme.field_bg = TERM_GRAY;
    htk_theme.sel_bg = TERM_BLUE;
    htk_theme.accent = TERM_BRIGHT_CYAN;
    htk_theme.menu_bg = TERM_BLUE;
    htk_theme.tool_bg = TERM_GRAY;
    htk_theme.tool_fg = TERM_BRIGHT_WHITE;
  } else if (index == 2) {  // Light
    htk_theme.desk_fg = TERM_WHITE;
    htk_theme.desk_bg = TERM_BRIGHT_WHITE;
    htk_theme.bg = TERM_BRIGHT_WHITE;
    htk_theme.fg = TERM_BLACK;
    htk_theme.dim = TERM_GRAY;
    htk_theme.title = TERM_BLACK;
    htk_theme.frame = TERM_BLUE;
    htk_theme.btn_bg = TERM_CYAN;
    htk_theme.field_bg = TERM_WHITE;
    htk_theme.field_fg = TERM_BLACK;
    htk_theme.sel_bg = TERM_BLUE;
    htk_theme.accent = TERM_RED;
    htk_theme.menu_bg = TERM_BLUE;
    htk_theme.tool_bg = TERM_WHITE;
  } else if (index == 3) {  // Teal
    htk_theme.bg = TERM_WHITE;
    htk_theme.fg = TERM_BLACK;
    htk_theme.dim = TERM_GRAY;
    htk_theme.title = TERM_BLACK;
    htk_theme.desk_fg = TERM_BLUE;
    htk_theme.desk_bg = TERM_CYAN;
    htk_theme.frame = TERM_BLUE;
    htk_theme.btn_bg = TERM_MAGENTA;
    htk_theme.btn_fg = TERM_BRIGHT_WHITE;
    htk_theme.accent = TERM_BLUE;
    htk_theme.menu_bg = TERM_BLUE;
    htk_theme.tool_bg = TERM_MAGENTA;
    htk_theme.tool_fg = TERM_BRIGHT_WHITE;
  } else if (index == 4) {  // Modern: slate surfaces with a cyan accent
    htk_theme.desk_fg = TERM_BLACK;
    htk_theme.desk_bg = TERM_BLACK;
    htk_theme.bg = TERM_BLACK;
    htk_theme.fg = TERM_WHITE;
    htk_theme.dim = TERM_GRAY;
    htk_theme.frame = TERM_CYAN;
    htk_theme.title = TERM_BRIGHT_WHITE;
    htk_theme.btn_bg = TERM_BLUE;
    htk_theme.btn_fg = TERM_BRIGHT_WHITE;
    htk_theme.focus_bg = TERM_BLUE;
    htk_theme.field_bg = TERM_BLACK;
    htk_theme.field_fg = TERM_BRIGHT_WHITE;
    htk_theme.sel_bg = TERM_CYAN;
    htk_theme.sel_fg = TERM_BLACK;
    htk_theme.bar_bg = TERM_BLUE;
    htk_theme.bar_fg = TERM_BRIGHT_WHITE;
    htk_theme.menu_bg = TERM_BLUE;
    htk_theme.menu_fg = TERM_BRIGHT_WHITE;
    htk_theme.tool_bg = TERM_GRAY;
    htk_theme.tool_fg = TERM_BRIGHT_WHITE;
    htk_theme.accent = TERM_CYAN;
    if (TermColorDepth > 16) {
      htk_theme.desk_bg = TermColorRgb(11, 16, 26);
      htk_theme.desk_fg = htk_theme.desk_bg;
      htk_theme.bg = TermColorRgb(17, 24, 39);
      htk_theme.field_bg = TermColorRgb(15, 23, 42);
      htk_theme.menu_bg = TermColorRgb(30, 41, 59);
      htk_theme.tool_bg = TermColorRgb(51, 65, 85);
      htk_theme.bar_bg = htk_theme.menu_bg;
      htk_theme.btn_bg = htk_theme.tool_bg;
      htk_theme.focus_bg = TermColorRgb(37, 99, 150);
      htk_theme.sel_bg = TermColorRgb(103, 232, 249);
      htk_theme.frame = htk_theme.sel_bg;
      htk_theme.accent = htk_theme.sel_bg;
    }
  } else if (index == 5) {  // Serial: basic ANSI colors and ASCII drawing
    htk_theme.ascii = TRUE;
    htk_theme.desk_fg = TERM_BLACK;
    htk_theme.desk_bg = TERM_BLACK;
    htk_theme.bg = TERM_BLACK;
    htk_theme.fg = TERM_WHITE;
    htk_theme.dim = TERM_WHITE;
    htk_theme.frame = TERM_WHITE;
    htk_theme.title = TERM_BLACK;
    htk_theme.btn_bg = TERM_WHITE;
    htk_theme.btn_fg = TERM_BLACK;
    htk_theme.focus_bg = TERM_BLUE;
    htk_theme.field_bg = TERM_BLACK;
    htk_theme.field_fg = TERM_WHITE;
    htk_theme.sel_bg = TERM_WHITE;
    htk_theme.sel_fg = TERM_BLACK;
    htk_theme.bar_bg = TERM_WHITE;
    htk_theme.bar_fg = TERM_BLACK;
    htk_theme.menu_bg = TERM_WHITE;
    htk_theme.menu_fg = TERM_BLACK;
    htk_theme.tool_bg = TERM_BLUE;
    htk_theme.tool_fg = TERM_WHITE;
    htk_theme.accent = TERM_WHITE;
  } else if (index == 6) HtkThemeLightBorland;
  htk_dirty = TRUE;
}

class HtkSettingsConfig
{
  I64 theme, desk_rgb, bar_rgb, frame_rgb;
  I64 bar_always, bar_clock, dim_inactive, vim_mode;
  I64 move_key, move_mods, resize_key, resize_mods;
};

I64 HtkSettingsIniNumber(CStrs *text)
{
  I64 i = 0, number = 0;
  Bool negative = FALSE;

  if (!text || StrsEmpty(text))
    return -1;
  if (*text->a == '-') {
    negative = TRUE;
    i++;
  }
  if (i >= StrsLen(text))
    return -1;
  while (i < StrsLen(text)) {
    if (text->a[i] < '0' || text->a[i] > '9')
      return -1;
    number = number * 10 + text->a[i] - '0';
    i++;
  }
  if (negative)
    number = -number;
  return number;
}

Bool HtkSettingsIniPair(CIni *ini, CStrs *section, CStrs *name,
  CStrs *value)
{
  HtkSettingsConfig *config = ini->user(HtkSettingsConfig *);
  I64 number, key, mods;

  if (!value || !StrsEqualsS(section, "htk"))
    return TRUE;
  if (StrsEqualsS(name, "move_key") || StrsEqualsS(name, "resize_key")) {
    if (HtkWindowKeyParse(value, &key, &mods)) {
      if (StrsEqualsS(name, "move_key")) {
        config->move_key = key;
        config->move_mods = mods;
      } else {
        config->resize_key = key;
        config->resize_mods = mods;
      }
    }
    return TRUE;
  }
  number = HtkSettingsIniNumber(value);
  if (!StrsEqualsS(name, "theme") && number < 0)
    return TRUE;
  if (StrsEqualsS(name, "theme"))
    config->theme = number;
  else if (StrsEqualsS(name, "desk_rgb"))
    config->desk_rgb = number;
  else if (StrsEqualsS(name, "bar_rgb"))
    config->bar_rgb = number;
  else if (StrsEqualsS(name, "frame_rgb"))
    config->frame_rgb = number;
  else if (StrsEqualsS(name, "bar_always"))
    config->bar_always = number;
  else if (StrsEqualsS(name, "bar_clock"))
    config->bar_clock = number;
  else if (StrsEqualsS(name, "dim_inactive"))
    config->dim_inactive = number;
  else if (StrsEqualsS(name, "vim_mode") && number <= 1)
    config->vim_mode = number;
  return TRUE;
}

I64 HtkSettingsColorFromRgb(I64 rgb)
{
  if (TermColorDepth > 16)
    return TermColorRgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF);
  return TermRgbToBasic(rgb);
}

// Load a deliberately small, forwards-compatible [htk] section from the
// user's home directory.  Unknown keys are ignored by the inih callback.
Bool HtkSettingsLoadText(U8 *text)
{
  HtkSettingsConfig config;
  CIni ini;

  if (!text)
    return FALSE;
  MemSet(&config, 0xFF, sizeof(HtkSettingsConfig));
  ini = IniParseS(text, &HtkSettingsIniPair, &config);
  if (!ini.ok)
    return FALSE;
  if (config.move_key < 0) {
    config.move_key = htk_move_key;
    config.move_mods = htk_move_mods;
  }
  if (config.resize_key < 0) {
    config.resize_key = htk_resize_key;
    config.resize_mods = htk_resize_mods;
  }
  HtkWindowSetKeys(config.move_key, config.move_mods,
    config.resize_key, config.resize_mods);
  if (config.theme >= 0 && config.theme < HTK_THEME_COUNT)
    HtkThemePreset(config.theme);
  if (config.desk_rgb >= 0)
    htk_theme.desk_bg = HtkSettingsColorFromRgb(config.desk_rgb);
  if (config.bar_rgb >= 0)
    htk_theme.bar_bg = HtkSettingsColorFromRgb(config.bar_rgb);
  if (config.frame_rgb >= 0)
    htk_theme.frame = HtkSettingsColorFromRgb(config.frame_rgb);
  if (config.desk_rgb >= 0)
    htk_theme.desk_fg = HtkDimColor(htk_theme.desk_bg);
  if (config.bar_always >= 0)
    htk_bar_always = config.bar_always != 0;
  if (config.bar_clock >= 0)
    htk_bar_clock = config.bar_clock != 0;
  if (config.dim_inactive >= 0)
    htk_dim_inactive = config.dim_inactive != 0;
  if (config.vim_mode >= 0)
    HtkVimSet(config.vim_mode != 0);
  if (htk_bar_clock)
    HtkHookAdd(0, 10000, &HtkClockTick, 0, 0);
  htk_desk_custom = -1;
  htk_bar_custom = -1;
  htk_frame_custom = -1;
  if (htk_theme.desk_bg >= 16)
    htk_desk_custom = htk_theme.desk_bg;
  if (htk_theme.bar_bg >= 16)
    htk_bar_custom = htk_theme.bar_bg;
  if (htk_theme.frame >= 16)
    htk_frame_custom = htk_theme.frame;
  htk_settings_saved = TRUE;
  return TRUE;
}

Bool HtkSettingsLoad()
{
  U8 *path = EnvHome, *file, *text;
  Bool ok;

  if (!path)
    return FALSE;
  file = MStrPrint("%s/htk.ini", path);
  Free(path);
  text = FileRead(file);
  Free(file);
  ok = HtkSettingsLoadText(text);
  Free(text);
  return ok;
}

Bool HtkSettingsSaved()
{
  return htk_settings_saved;
}

// --- settings dialog -------------------------------------------------------

HtkCtl *htk_settings;  // the open dialog, NULL otherwise
HtkCtl *htk_set_theme, *htk_set_desk, *htk_set_bar_color, *htk_set_frame_color;
HtkCtl *htk_set_bar, *htk_set_clock;
HtkCtl *htk_set_dim, *htk_set_vim;
HtkCtl *htk_set_move, *htk_set_resize;

U0 HtkSettingsSync();

class HtkSettingsColor
{
  HtkCtl *combo;
  I64 *color, *custom;
  U8 *title;
  Bool desktop;
};

U0 HtkClockTick(I64 a, I64 b)
{
  if (htk_bar_clock)
    htk_dirty = TRUE;
}

Bool HtkSettingsApply(HtkCtl *button)
{
  I64 desk = htk_set_desk->value;
  Bool clock_was = htk_bar_clock;
  CStrs move, resize;
  I64 move_key, move_mods, resize_key, resize_mods;

  StrsInitS(&move, htk_set_move->text);
  StrsInitS(&resize, htk_set_resize->text);
  if (!HtkWindowKeyParse(&move, &move_key, &move_mods) ||
    !HtkWindowKeyParse(&resize, &resize_key, &resize_mods) ||
    !HtkWindowSetKeys(move_key, move_mods, resize_key, resize_mods)) {
    HtkNotify("Use distinct valid shortcuts, or None to disable", 3000);
    return FALSE;
  }

  if (htk_set_theme->value >= 0)
    HtkThemePreset(htk_set_theme->value);
  if (desk >= 0) {
    htk_theme.desk_bg = desk;
    htk_desk_custom = -1;
  } else if (htk_desk_custom >= 0) {
    htk_theme.desk_bg = htk_desk_custom;
  }
  if (htk_set_bar_color->value >= 0) {
    htk_theme.bar_bg = htk_set_bar_color->value;
    htk_bar_custom = -1;
  } else if (htk_bar_custom >= 0) {
    htk_theme.bar_bg = htk_bar_custom;
  }
  if (htk_set_frame_color->value >= 0) {
    htk_theme.frame = htk_set_frame_color->value;
    htk_frame_custom = -1;
  } else if (htk_frame_custom >= 0) {
    htk_theme.frame = htk_frame_custom;
  }
  if (desk >= 0 || htk_desk_custom >= 0)  // pattern in a darker shade of it
    htk_theme.desk_fg = HtkDimColor(htk_theme.desk_bg);
  htk_bar_always = htk_set_bar->value;
  htk_bar_clock = htk_set_clock->value;
  htk_dim_inactive = htk_set_dim->value;
  HtkVimSet(htk_set_vim->value != 0);
  if (htk_bar_clock && !clock_was)
    HtkHookAdd(0, 10000, &HtkClockTick, 0, 0);  // keep HH:MM fresh
  htk_dirty = TRUE;
  return TRUE;
}

U8 *HtkSettingsText()
{
  U8 *move = HtkWindowKeyName(htk_move_key, htk_move_mods);
  U8 *resize = HtkWindowKeyName(htk_resize_key, htk_resize_mods);
  U8 *text = MStrPrint("[htk]\ntheme = %d\ndesk_rgb = %d\nbar_rgb = %d\n"
    "frame_rgb = %d\nbar_always = %d\nbar_clock = %d\ndim_inactive = %d\n"
    "move_key = %s\nresize_key = %s\nvim_mode = %d\n",
    htk_desk_theme, TermColorToRgb(htk_theme.desk_bg),
    TermColorToRgb(htk_theme.bar_bg), TermColorToRgb(htk_theme.frame),
    htk_bar_always, htk_bar_clock, htk_dim_inactive, move, resize, htk_vim_mode);

  Free(move);
  Free(resize);
  return text;
}

U0 HtkSettingsSave(HtkCtl *button)
{
  U8 *home, *file, *text;
  Bool ok;

  if (!HtkSettingsApply(button))
    return;
  home = EnvHome;
  if (!home) {
    HtkNotify("Cannot find the home directory", 3000);
    return;
  }
  file = MStrPrint("%s/htk.ini", home);
  Free(home);
  text = HtkSettingsText;
  ok = FileWrite(file, text);
  Free(text);
  Free(file);
  if (ok) {
    htk_settings_saved = TRUE;
    HtkNotify("Settings saved to ~/htk.ini", 2500);
  } else
    HtkNotify("Could not save ~/htk.ini", 3000);
}

U0 HtkSettingsReset(HtkCtl *button)
{
  U8 *home, *file;

  HtkThemePreset(0);
  HtkWindowKeysDefault;
  htk_desk_custom = -1;
  htk_bar_custom = -1;
  htk_frame_custom = -1;
  htk_bar_always = TRUE;
  htk_bar_clock = FALSE;
  htk_dim_inactive = FALSE;
  HtkVimSet(FALSE);
  htk_settings_saved = FALSE;
  HtkSettingsSync;
  home = EnvHome;
  if (home) {
    file = MStrPrint("%s/htk.ini", home);
    remove(file);
    Free(file);
    Free(home);
  }
  HtkNotify("Settings reset", 2000);
  htk_dirty = TRUE;
}

// Theme selection is immediately visible.  This also makes the combobox a
// useful preview rather than requiring users to infer that Apply is needed.
U0 HtkSettingsTheme(HtkCtl *combo)
{
  if (combo->value >= 0 && combo->value < HTK_THEME_COUNT)
    HtkThemePreset(combo->value);
}

// Shared picker action for every named-color settings row.
U0 HtkSettingsPickColor(HtkCtl *button)
{
  HtkSettingsColor *state = button->data(HtkSettingsColor *);
  I64 rgb = HtkColorPick(state->title, TermColorToRgb(*state->color));

  if (rgb < 0)
    return;
  if (TermColorDepth > 16)
    *state->custom = TermColorRgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF,
      rgb & 0xFF);
  else
    *state->custom = TermRgbToBasic(rgb);
  *state->color = *state->custom;
  if (state->desktop)
    htk_theme.desk_fg = HtkDimColor(*state->color);  // subtle ▒ pattern
  state->combo->value = -1;
  htk_dirty = TRUE;
}

U0 HtkSettingsClose(HtkCtl *button)
{
  HtkWindowClose(htk_settings);
  htk_settings = NULL;
}

HtkCtl *HtkSettingsLabel(HtkCtl *grid, U8 *text, I64 row)
{
  HtkCtl *l = HtkNew(HTK_LABEL);

  HtkSetText(l, text);
  l->col = 0;
  l->row = row;
  HtkAdd(grid, l);
  return l;
}

HtkCtl *HtkSettingsCell(HtkCtl *grid, HtkCtl *c, I64 row)
{
  c->col = 1;
  c->row = row;
  c->expand = TRUE;
  HtkAdd(grid, c);
  return c;
}

// Named palette combo plus a picker button.  The state object lets the one
// picker callback update any theme color without duplicated plumbing.
HtkCtl *HtkSettingsColorRow(HtkCtl *grid, U8 *label, I64 row, I64 *color,
  I64 *custom, Bool desktop)
{
  HtkCtl *box = HtkNew(HTK_BOX);
  HtkCtl *combo = HtkComboNew;
  HtkCtl *pick = HtkButtonNew(" Pick... ");
  HtkSettingsColor *state = CAlloc(sizeof(HtkSettingsColor));
  I64 i;

  HtkSettingsLabel(grid, label, row);
  combo->expand = TRUE;
  for (i = 0; i < HTK_COLOR_COUNT; i++)
    HtkComboAdd(combo, htk_color_names[i]);
  combo->value = -1;
  if (*color < 16)
    combo->value = *color;
  state->combo = combo;
  state->color = color;
  state->custom = custom;
  state->title = label;
  state->desktop = desktop;
  pick->data = state;
  pick->changed = &HtkSettingsPickColor;
  HtkAdd(box, combo);
  HtkAdd(box, pick);
  HtkSettingsCell(grid, box, row);
  return combo;
}

// Refresh the dialog after Reset without recreating the window or leaving
// stale combobox values behind.
U0 HtkSettingsSync()
{
  U8 *move, *resize;

  if (!htk_set_theme)
    return;
  htk_set_theme->value = htk_desk_theme;
  htk_set_desk->value = -1;
  htk_set_bar_color->value = -1;
  htk_set_frame_color->value = -1;
  if (htk_theme.desk_bg < 16)
    htk_set_desk->value = htk_theme.desk_bg;
  if (htk_theme.bar_bg < 16)
    htk_set_bar_color->value = htk_theme.bar_bg;
  if (htk_theme.frame < 16)
    htk_set_frame_color->value = htk_theme.frame;
  htk_set_bar->value = htk_bar_always;
  htk_set_clock->value = htk_bar_clock;
  htk_set_dim->value = htk_dim_inactive;
  htk_set_vim->value = htk_vim_mode;
  move = HtkWindowKeyName(htk_move_key, htk_move_mods);
  resize = HtkWindowKeyName(htk_resize_key, htk_resize_mods);
  HtkSetText(htk_set_move, move);
  HtkSetText(htk_set_resize, resize);
  htk_set_move->cursor = StrLen(move);
  htk_set_resize->cursor = StrLen(resize);
  Free(move);
  Free(resize);
}

#if UI_HTK_DESKTERM
U0 HtkTerminalOpen()
{
  HtkCtl *term = HtkTerminalNew(HTK_GRID);
  HtkCtl *win = HtkDialogNew("Terminal", term);
  win->w = 60;
  win->h += 10;
}

U0 HtkAppTerminal(HtkCtl *item)
{
  HtkTerminalOpen;
}
#endif

U0 HtkSettingsOpen()
{
  HtkCtl *box, *grid, *row, *save, *reset, *close, *pick, *spacer;
  I64 i;
  U8 *move, *resize;

  if (htk_settings && !htk_settings->closed) {
    HtkWindowRaise(htk_settings);
    return;
  }
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;
  grid = HtkNew(HTK_GRID);
  HtkSettingsLabel(grid, "Theme", 0);
  htk_set_theme = HtkSettingsCell(grid, HtkComboNew, 0);
  htk_set_theme->changed = &HtkSettingsTheme;
  for (i = 0; i < HTK_THEME_COUNT; i++)
    HtkComboAdd(htk_set_theme, htk_theme_names[i]);
  if (htk_desk_theme >= 0 && htk_desk_theme < HTK_THEME_COUNT)
    htk_set_theme->value = htk_desk_theme;
  htk_set_desk = HtkSettingsColorRow(grid, "Desktop color", 1,
    &htk_theme.desk_bg, &htk_desk_custom, TRUE);
  htk_set_bar_color = HtkSettingsColorRow(grid, "Window bar color", 2,
    &htk_theme.bar_bg, &htk_bar_custom, FALSE);
  htk_set_frame_color = HtkSettingsColorRow(grid, "Window border color", 3,
    &htk_theme.frame, &htk_frame_custom, FALSE);
  move = HtkWindowKeyName(htk_move_key, htk_move_mods);
  resize = HtkWindowKeyName(htk_resize_key, htk_resize_mods);
  HtkSettingsLabel(grid, "Move shortcut", 4);
  htk_set_move = HtkSettingsCell(grid, HtkEntryNew(move, 63), 4);
  HtkSettingsLabel(grid, "Resize shortcut", 5);
  htk_set_resize = HtkSettingsCell(grid, HtkEntryNew(resize, 63), 5);
  Free(move);
  Free(resize);
  HtkAdd(box, grid);
  htk_set_bar = HtkCheckboxNew("Always show the window bar", htk_bar_always);
  HtkAdd(box, htk_set_bar);
  htk_set_clock = HtkCheckboxNew("Show the clock", htk_bar_clock);
  HtkAdd(box, htk_set_clock);
  htk_set_dim = HtkCheckboxNew("Dim unfocused windows", htk_dim_inactive);
  HtkAdd(box, htk_set_dim);
  htk_set_vim = HtkCheckboxNew("Vim mode for text editors", htk_vim_mode);
  HtkAdd(box, htk_set_vim);
  spacer = HtkNew(HTK_LABEL);  // takes the spare height, so the buttons
  spacer->expand = TRUE;       // stay anchored to the bottom-right corner
  HtkAdd(box, spacer);
  row = HtkNew(HTK_BOX);
  spacer = HtkNew(HTK_LABEL);
  spacer->expand = TRUE;
  HtkAdd(row, spacer);
  reset = HtkButtonNew(" Reset ");
  reset->changed = &HtkSettingsReset;
  HtkAdd(row, reset);
  save = HtkButtonNew(" Save ");
  save->changed = &HtkSettingsSave;
  HtkAdd(row, save);
  close = HtkButtonNew(" Close ");
  close->changed = &HtkSettingsClose;
  HtkAdd(row, close);
  HtkAdd(box, row);
  htk_settings = HtkDialogNew("Settings", box);
  htk_settings->w += 8;
}

// --- [App] menu ------------------------------------------------------------

HtkCtl *htk_app_menu;

U0 HtkAppLaunch(HtkCtl *item)
{
  HtkApp *app = item->data(HtkApp *);

  if (app && app->entry)
    app->entry(app->data);
}

U0 HtkAppMenuAdd(HtkApp *app)
{
  HtkCtl *item;

  if (!htk_app_menu || !app)
    return;
  item = HtkMenuItem(htk_app_menu, app->name);
  item->data = app;
  item->changed = &HtkAppLaunch;
}

// Register a launcher before or after HtkMain begins.  The callback is free
// to create any number of windows; when all close the desktop remains ready
// at App until HtkQuit is called.
HtkApp *HtkAppRegister(U8 *name, I64 entry, I64 data=0)
{
  HtkApp *app = CAlloc(sizeof(HtkApp));
  HtkApp **at = &htk_apps;

  app->name = StrNew(name);
  app->entry = entry;
  app->data = data;
  while (*at)
    at = &(*at)->next;
  *at = app;
  HtkAppMenuAdd(app);
  return app;
}

U0 HtkAppSettings(HtkCtl *item)
{
  HtkSettingsOpen;
}

U0 HtkAppQuit(HtkCtl *item)
{
  HtkConfirmQuit;
}

U0 HtkAppMenuOpen(I64 x, I64 y)
{
  if (!htk_app_menu) {
    htk_app_menu = HtkContextMenuNew;
    if (htk_apps) {
      HtkApp *app = htk_apps;
      while (app) {
        HtkAppMenuAdd(app);
        app = app->next;
      }
      HtkMenuSeparator(htk_app_menu);
    }
#if UI_HTK_DESKTERM
    HtkMenuItem(htk_app_menu, "Terminal...")->changed = &HtkAppTerminal;
#endif
    HtkMenuItem(htk_app_menu, "Settings...")->changed = &HtkAppSettings;
    HtkMenuItem(htk_app_menu, "Quit")->changed = &HtkAppQuit;
  }
  // Pop from the row below the App trigger (or immediately above the bottom
  // bar when the picker flips upward to stay on screen).
  HtkMenuOpenAt(htk_app_menu, x, y + 1);
}
