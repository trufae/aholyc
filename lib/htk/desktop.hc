// Desktop layer: the [App] menu on the window bar (also the desktop's right
// click menu) with Refresh, Settings... and Quit, and the settings dialog
// that picks a color theme, the desktop color, whether the window bar is
// always shown, whether it carries a clock and whether unfocused windows
// are dimmed. Build with -DHTK_NODESK to leave all of this out.

#define HTK_THEME_COUNT 4
U8 *htk_theme_names[HTK_THEME_COUNT] = {"Borland", "Dark", "Light", "Teal"};

#define HTK_COLOR_COUNT 16
U8 *htk_color_names[HTK_COLOR_COUNT] = {"black", "red", "green", "yellow",
    "blue", "magenta", "cyan", "white", "gray", "bright red", "bright green",
  "bright yellow", "bright blue", "bright magenta", "bright cyan",
  "bright white"};

I64 htk_desk_theme;  // current preset index

U0 HtkThemePreset(I64 index)
{
  HtkThemeDefault;
  htk_desk_theme = index;
  if (index == 1) {  // Dark
    htk_theme.desk_fg = TERM_GRAY;
    htk_theme.desk_bg = TERM_BLACK;
    htk_theme.bg = TERM_BLACK;
    htk_theme.fg = TERM_WHITE;
    htk_theme.frame = TERM_BRIGHT_CYAN;
    htk_theme.title = TERM_WHITE;
    htk_theme.btn_bg = TERM_BLUE;
    htk_theme.btn_fg = TERM_BRIGHT_WHITE;
    htk_theme.focus_bg = TERM_MAGENTA;
    htk_theme.field_bg = TERM_GRAY;
    htk_theme.sel_bg = TERM_BLUE;
  } else if (index == 2) {  // Light
    htk_theme.desk_fg = TERM_WHITE;
    htk_theme.desk_bg = TERM_BRIGHT_WHITE;
    htk_theme.bg = TERM_BRIGHT_WHITE;
    htk_theme.frame = TERM_BLUE;
    htk_theme.btn_bg = TERM_CYAN;
    htk_theme.field_bg = TERM_WHITE;
    htk_theme.field_fg = TERM_BLACK;
    htk_theme.sel_bg = TERM_BLUE;
    htk_theme.accent = TERM_RED;
  } else if (index == 3) {  // Teal
    htk_theme.desk_fg = TERM_BLUE;
    htk_theme.desk_bg = TERM_CYAN;
    htk_theme.frame = TERM_BRIGHT_YELLOW;
    htk_theme.btn_bg = TERM_MAGENTA;
    htk_theme.btn_fg = TERM_BRIGHT_WHITE;
  }
  htk_dirty = TRUE;
}

// --- settings dialog -------------------------------------------------------

HtkCtl *htk_settings;  // the open dialog, NULL otherwise
HtkCtl *htk_set_theme, *htk_set_desk, *htk_set_bar, *htk_set_clock;
HtkCtl *htk_set_dim;
I64 htk_desk_custom = -1;  // desktop color chosen with Pick..., or -1

U0 HtkClockTick(I64 a, I64 b)
{
  if (htk_bar_clock)
    htk_dirty = TRUE;
}

U0 HtkSettingsApply(HtkCtl *button)
{
  I64 desk = htk_set_desk->value;
  Bool clock_was = htk_bar_clock;

  if (htk_set_theme->value >= 0)
    HtkThemePreset(htk_set_theme->value);
  if (desk >= 0) {
    htk_theme.desk_bg = desk;
    htk_desk_custom = -1;
  } else if (htk_desk_custom >= 0) {
    htk_theme.desk_bg = htk_desk_custom;
  }
  if (desk >= 0 || htk_desk_custom >= 0)  // pattern in a darker shade of it
    htk_theme.desk_fg = HtkDimColor(htk_theme.desk_bg);
  htk_bar_always = htk_set_bar->value;
  htk_bar_clock = htk_set_clock->value;
  htk_dim_inactive = htk_set_dim->value;
  if (htk_bar_clock && !clock_was)
    HtkHookAdd(0, 10000, &HtkClockTick, 0, 0);  // keep HH:MM fresh
  htk_dirty = TRUE;
}

// Any color the terminal can show, through the color picker.
U0 HtkSettingsPickDesk(HtkCtl *button)
{
  I64 rgb = HtkColorPick("Desktop color", TermColorToRgb(htk_theme.desk_bg));

  if (rgb < 0)
    return;
  if (TermColorDepth > 16)
    htk_desk_custom = TermColorRgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF,
      rgb & 0xFF);
  else
    htk_desk_custom = TermRgbToBasic(rgb);
  htk_theme.desk_bg = htk_desk_custom;
  htk_theme.desk_fg = HtkDimColor(htk_desk_custom);  // subtle ▒ pattern
  htk_set_desk->value = -1;  // the combo no longer describes it
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

U0 HtkSettingsOpen()
{
  HtkCtl *box, *grid, *row, *apply, *close, *pick, *spacer;
  I64 i;

  if (htk_settings && !htk_settings->closed) {
    HtkWindowRaise(htk_settings);
    return;
  }
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;
  grid = HtkNew(HTK_GRID);
  HtkSettingsLabel(grid, "Theme", 0);
  htk_set_theme = HtkSettingsCell(grid, HtkComboNew, 0);
  for (i = 0; i < HTK_THEME_COUNT; i++)
    HtkComboAdd(htk_set_theme, htk_theme_names[i]);
  htk_set_theme->value = htk_desk_theme;
  HtkSettingsLabel(grid, "Desktop color", 1);
  row = HtkNew(HTK_BOX);
  htk_set_desk = HtkComboNew;
  htk_set_desk->expand = TRUE;
  for (i = 0; i < HTK_COLOR_COUNT; i++)
    HtkComboAdd(htk_set_desk, htk_color_names[i]);
  htk_set_desk->value = -1;
  if (htk_theme.desk_bg < 16)
    htk_set_desk->value = htk_theme.desk_bg;
  HtkAdd(row, htk_set_desk);
  pick = HtkButtonNew(" Pick... ");
  pick->changed = &HtkSettingsPickDesk;
  HtkAdd(row, pick);
  HtkSettingsCell(grid, row, 1);
  HtkAdd(box, grid);
  htk_set_bar = HtkCheckboxNew("Always show the window bar", htk_bar_always);
  HtkAdd(box, htk_set_bar);
  htk_set_clock = HtkCheckboxNew("Show the clock", htk_bar_clock);
  HtkAdd(box, htk_set_clock);
  htk_set_dim = HtkCheckboxNew("Dim unfocused windows", htk_dim_inactive);
  HtkAdd(box, htk_set_dim);
  spacer = HtkNew(HTK_LABEL);  // takes the spare height, so the buttons
  spacer->expand = TRUE;       // stay anchored to the bottom-right corner
  HtkAdd(box, spacer);
  row = HtkNew(HTK_BOX);
  spacer = HtkNew(HTK_LABEL);
  spacer->expand = TRUE;
  HtkAdd(row, spacer);
  apply = HtkButtonNew(" Apply ");
  apply->changed = &HtkSettingsApply;
  HtkAdd(row, apply);
  close = HtkButtonNew(" Close ");
  close->changed = &HtkSettingsClose;
  HtkAdd(row, close);
  HtkAdd(box, row);
  htk_settings = HtkDialogNew("Settings", box);
  htk_settings->w += 8;
}

// --- [App] menu ------------------------------------------------------------

HtkCtl *htk_app_menu;

U0 HtkAppRefresh(HtkCtl *item)
{
  htk_dirty = TRUE;
}

U0 HtkAppSettings(HtkCtl *item)
{
  HtkSettingsOpen;
}

U0 HtkAppQuit(HtkCtl *item)
{
  HtkQuit;
}

U0 HtkAppMenuOpen(I64 x, I64 y)
{
  if (!htk_app_menu) {
    htk_app_menu = HtkContextMenuNew;
    HtkMenuItem(htk_app_menu, "Refresh")->changed = &HtkAppRefresh;
    HtkMenuItem(htk_app_menu, "Settings...")->changed = &HtkAppSettings;
    HtkMenuItem(htk_app_menu, "Quit")->changed = &HtkAppQuit;
  }
  HtkMenuOpenAt(htk_app_menu, x, y);
}
