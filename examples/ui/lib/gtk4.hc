// GTK4 backend for ui.hc (linux, and macOS via Homebrew)
// @pkgconfig=gtk4

extern U0 gtk_init();
extern I64 gtk_window_new();
extern U0 gtk_window_set_title(I64 win, U8 *title);
extern U0 gtk_window_set_default_size(I64 win, I64 w, I64 h);
extern U0 gtk_window_set_child(I64 win, I64 child);
extern U0 gtk_window_present(I64 win);
extern I64 gtk_box_new(I64 orientation, I64 spacing);
extern U0 gtk_box_append(I64 box, I64 child);
extern U0 gtk_box_prepend(I64 box, I64 child);
extern I64 gtk_grid_new();
extern U0 gtk_grid_attach(I64 g, I64 c, I64 col, I64 row, I64 cs, I64 rs);
extern U0 gtk_grid_set_row_spacing(I64 g, I64 px);
extern U0 gtk_grid_set_column_spacing(I64 g, I64 px);
extern I64 gtk_label_new(U8 *text);
extern U0 gtk_label_set_text(I64 label, U8 *text);
extern I64 gtk_button_new_with_label(U8 *text);
extern I64 gtk_entry_new();
extern I64 gtk_editable_get_text(I64 e);
extern U0 gtk_editable_set_text(I64 e, U8 *text);
extern I64 gtk_check_button_new_with_label(U8 *text);
extern U0 gtk_check_button_set_active(I64 c, I64 on);
extern I64 gtk_check_button_get_active(I64 c);
extern I64 gtk_scale_new_with_range(I64 orient, F64 min, F64 max, F64 step);
extern F64 gtk_range_get_value(I64 r);
extern I64 gtk_progress_bar_new();
extern U0 gtk_progress_bar_set_fraction(I64 p, F64 f);
extern I64 gtk_separator_new(I64 orient);
extern I64 gtk_drawing_area_new();
extern U0 gtk_drawing_area_set_content_width(I64 a, I64 px);
extern U0 gtk_drawing_area_set_content_height(I64 a, I64 px);
extern U0 gtk_drawing_area_set_draw_func(I64 a, I64 fn, I64 data, I64 dtor);
extern U0 gtk_widget_queue_draw(I64 w);
extern U0 gtk_widget_set_margin_top(I64 w, I64 px);
extern U0 gtk_widget_set_margin_bottom(I64 w, I64 px);
extern U0 gtk_widget_set_margin_start(I64 w, I64 px);
extern U0 gtk_widget_set_margin_end(I64 w, I64 px);
extern U0 gtk_widget_insert_action_group(I64 w, U8 *prefix, I64 grp);
extern I64 gtk_popover_menu_bar_new_from_model(I64 model);
extern I64 g_menu_new();
extern U0 g_menu_append(I64 m, U8 *label, U8 *action);
extern U0 g_menu_append_submenu(I64 m, U8 *label, I64 sub);
extern I64 g_simple_action_new(U8 *name, I64 ptype);
extern I64 g_simple_action_group_new();
extern U0 g_action_map_add_action(I64 map, I64 action);
extern I64 g_signal_connect_data(I64 obj, U8 *sig, I64 cb, I64 data,
  I64 destroy, I64 flags);
extern I64 g_main_loop_new(I64 ctx, I64 running);
extern U0 g_main_loop_run(I64 loop);
extern U0 g_main_loop_quit(I64 loop);
extern U0 cairo_set_source_rgb(I64 cr, F64 r, F64 g, F64 b);
extern U0 cairo_rectangle(I64 cr, F64 x, F64 y, F64 w, F64 h);
extern U0 cairo_fill(I64 cr);
extern U0 cairo_move_to(I64 cr, F64 x, F64 y);
extern U0 cairo_line_to(I64 cr, F64 x, F64 y);
extern U0 cairo_stroke(I64 cr);
extern U0 cairo_set_line_width(I64 cr, F64 w);
extern U0 gtk_window_set_modal(I64 win, I64 on);
extern U0 gtk_window_set_transient_for(I64 win, I64 parent);
extern U0 gtk_window_destroy(I64 win);
extern I64 gtk_alert_dialog_get_type();
extern U0 gtk_alert_dialog_show(I64 dlg, I64 parent);
extern I64 gtk_file_dialog_new();
extern U0 gtk_file_dialog_open(I64 d, I64 parent, I64 cancel, I64 cb, I64 data);
extern I64 gtk_file_dialog_open_finish(I64 d, I64 res, I64 err);
extern U8 *g_file_get_path(I64 f);
extern I64 g_object_new_with_properties(I64 type, I64 n, U8 **names, U0 *vals);
extern U0 g_value_init(U0 *gv, I64 type);
extern U0 g_value_set_string(U0 *gv, U8 *s);
extern I64 g_main_context_iteration(I64 ctx, I64 block);
extern U0 g_object_unref(I64 obj);
extern I64 gtk_drop_down_new_from_strings(U8 **strs);
extern I64 gtk_string_list_new(U8 **strs);
extern U0 gtk_string_list_append(I64 l, U8 *s);
extern I64 gtk_drop_down_new(I64 model, I64 expr);
extern U0 gtk_drop_down_set_selected(I64 d, I64 pos);
extern I64 gtk_drop_down_get_selected(I64 d);
extern I64 gtk_check_button_get_group();  // not called; group via set_group
extern U0 gtk_check_button_set_group(I64 c, I64 group);
extern I64 gtk_spin_button_new_with_range(F64 min, F64 max, F64 step);
extern I64 gtk_spin_button_get_value_as_int(I64 s);
extern I64 gtk_text_view_new();
extern I64 gtk_text_view_get_buffer(I64 tv);
extern U0 gtk_text_buffer_set_text(I64 b, U8 *text, I64 len);
extern U0 gtk_entry_set_visibility(I64 e, I64 vis);
extern I64 gtk_frame_new(U8 *label);
extern U0 gtk_frame_set_child(I64 f, I64 child);
extern I64 gtk_notebook_new();
extern U0 gtk_notebook_append_page(I64 nb, I64 child, I64 tab_label);
extern U0 gtk_widget_set_sensitive(I64 w, I64 on);
extern U0 gtk_widget_set_visible(I64 w, I64 on);
extern I64 g_timeout_add(I64 ms, I64 fn, I64 data);
extern I64 g_idle_add(I64 fn, I64 data);
extern I64 gtk_paned_new(I64 orient);
extern U0 gtk_paned_set_start_child(I64 p, I64 c);
extern U0 gtk_paned_set_end_child(I64 p, I64 c);
extern U0 gtk_paned_set_position(I64 p, I64 pos);
extern I64 gtk_scrolled_window_new();
extern U0 gtk_scrolled_window_set_child(I64 s, I64 c);
extern U0 gtk_widget_set_hexpand(I64 w, I64 on);
extern U0 gtk_widget_set_vexpand(I64 w, I64 on);
extern U0 gtk_widget_add_css_class(I64 w, U8 *cls);
extern U0 gtk_label_set_xalign(I64 l, F64 x);
extern I64 gtk_tree_store_newv(I64 n, I64 *types);
extern U0 gtk_tree_store_append(I64 store, U0 *iter, U0 *parent);
extern U0 gtk_tree_store_set_value(I64 store, U0 *iter, I64 col, U0 *val);
extern I64 gtk_tree_view_new_with_model(I64 model);
extern I64 gtk_tree_view_column_new();
extern I64 gtk_cell_renderer_text_new();
extern U0 gtk_tree_view_column_pack_start(I64 col, I64 rend, I64 expand);
extern U0 gtk_tree_view_column_add_attribute(I64 col, I64 rend, U8 *attr, I64 c);
extern I64 gtk_tree_view_append_column(I64 tv, I64 col);
extern U0 gtk_tree_view_set_headers_visible(I64 tv, I64 vis);
extern U0 gtk_tree_view_expand_all(I64 tv);
extern I64 gtk_tree_view_get_selection(I64 tv);
extern I64 gtk_tree_selection_get_selected(I64 sel, U0 *model, U0 *iter);
extern U0 gtk_tree_model_get_value(I64 model, U0 *iter, I64 col, U0 *val);
extern U0 g_value_set_pointer(U0 *v, I64 p);
extern I64 g_value_get_pointer(U0 *v);
extern U0 g_value_unset(U0 *v);

#define G_TYPE_STRING 64

I64 ui_gtk_loop = 0, ui_gtk_win = 0, ui_gtk_outer = 0, ui_gtk_nwin = 0;
I64 ui_gtk_bar = 0, ui_gtk_grp = 0, ui_gtk_nmenu = 0;
I64 ui_cr = 0;  // cairo context, valid inside a draw callback
I64 ui_dlg_done, ui_dlg_text, ui_dlg_gone;

U0 UiInit()
{
  gtk_init;
}

U0 UiQuit()
{
  if (ui_gtk_loop)
    g_main_loop_quit(ui_gtk_loop);
}

U0 UiGtkClicked(I64 obj, I64 data)
{
  UiFireClick(data);
}

U0 UiGtkMenuFire(I64 action, I64 param, I64 data)
{
  UiFireClick(data);
}

// notify::* signals pass (obj, GParamSpec*, data): needs the 3-arg shape,
// UiGtkClicked here would misread the pspec as its user data
U0 UiGtkNotify(I64 obj, I64 pspec, I64 data)
{
  UiFireClick(data);
}

U0 UiGtkDestroyed(I64 win, I64 data)
{
  ui_gtk_nwin--;
  if (ui_gtk_nwin <= 0)
    UiQuit;
}

U0 UiGtkDraw(I64 area, I64 cr, I64 w, I64 h, I64 data)
{
  ui_cr = cr;
  UiFireClick(data);
  ui_cr = 0;
}

UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320)
{
  ui_gtk_win = gtk_window_new;
  gtk_window_set_title(ui_gtk_win, title);
  gtk_window_set_default_size(ui_gtk_win, w, h);
  g_signal_connect_data(ui_gtk_win, "destroy", &UiGtkDestroyed, 0, 0, 0);
  ui_gtk_outer = gtk_box_new(1, 0);
  gtk_window_set_child(ui_gtk_win, ui_gtk_outer);
  ui_gtk_nwin++;
  UiCtl *c = UiCtlNew(UI_WINDOW, ui_gtk_win);
  c->kids = UiCtlNew(UI_BOX, ui_gtk_outer);  // per-window outer box
  return c;
}

UiCtl *UiBoxNew(Bool vertical=TRUE)
{
  I64 box = gtk_box_new(vertical, 20);
  gtk_widget_set_margin_top(box, 20);
  gtk_widget_set_margin_bottom(box, 20);
  gtk_widget_set_margin_start(box, 20);
  gtk_widget_set_margin_end(box, 20);
  return UiCtlNew(UI_BOX, box);
}

UiCtl *UiGridNew()
{
  I64 g = gtk_grid_new;
  gtk_grid_set_row_spacing(g, 10);
  gtk_grid_set_column_spacing(g, 10);
  return UiCtlNew(UI_GRID, g);
}

U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row)
{
  gtk_grid_attach(g->native, c->native, col, row, 1, 1);
}

UiCtl *UiLabelNew(U8 *text="")
{
  return UiCtlNew(UI_LABEL, gtk_label_new(text));
}

U0 UiLabelSetText(UiCtl *l, U8 *text)
{
  gtk_label_set_text(l->native, text);
}

UiCtl *UiButtonNew(U8 *text)
{
  UiCtl *c = UiCtlNew(UI_BUTTON, gtk_button_new_with_label(text));
  g_signal_connect_data(c->native, "clicked", &UiGtkClicked, c, 0, 0);
  return c;
}

UiCtl *UiEntryNew(U8 *text="")
{
  UiCtl *c = UiCtlNew(UI_ENTRY, gtk_entry_new);
  gtk_editable_set_text(c->native, text);
  g_signal_connect_data(c->native, "changed", &UiGtkClicked, c, 0, 0);
  return c;
}

U8 *UiEntryText(UiCtl *e)
{
  U8 *t = gtk_editable_get_text(e->native);
  return StrNew(t);
}

U0 UiEntrySetText(UiCtl *e, U8 *text)
{
  gtk_editable_set_text(e->native, text);
}

UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE)
{
  UiCtl *c = UiCtlNew(UI_CHECKBOX, gtk_check_button_new_with_label(text));
  gtk_check_button_set_active(c->native, checked);
  g_signal_connect_data(c->native, "toggled", &UiGtkClicked, c, 0, 0);
  return c;
}

Bool UiCheckboxChecked(UiCtl *c)
{
  return gtk_check_button_get_active(c->native) & 1;
}

UiCtl *UiSliderNew(I64 min=0, I64 max=100)
{
  F64 fmin = min, fmax = max;
  UiCtl *c = UiCtlNew(UI_SLIDER, gtk_scale_new_with_range(0, fmin, fmax, 1.0));
  g_signal_connect_data(c->native, "value-changed", &UiGtkClicked, c, 0, 0);
  return c;
}

I64 UiSliderValue(UiCtl *s)
{
  return gtk_range_get_value(s->native);
}

UiCtl *UiProgressNew()
{
  return UiCtlNew(UI_PROGRESS, gtk_progress_bar_new);
}

U0 UiProgressSet(UiCtl *p, I64 percent)
{
  F64 f = percent;
  gtk_progress_bar_set_fraction(p->native, f / 100.0);
}

UiCtl *UiSeparatorNew()
{
  return UiCtlNew(UI_SEP, gtk_separator_new(0));
}

UiCtl *UiCanvasNew(I64 w, I64 h, U0 *drawfn, U0 *data=NULL)
{
  I64 a = gtk_drawing_area_new;
  gtk_drawing_area_set_content_width(a, w);
  gtk_drawing_area_set_content_height(a, h);
  UiCtl *c = UiCtlNew(UI_CANVAS, a);
  c->w = w;
  c->h = h;
  UiOnClick(c, drawfn, data);
  gtk_drawing_area_set_draw_func(a, &UiGtkDraw, c, 0);
  return c;
}

U0 UiCanvasRedraw(UiCtl *c)
{
  gtk_widget_queue_draw(c->native);
}

U0 UiSetColor(F64 r, F64 g, F64 b)
{
  cairo_set_source_rgb(ui_cr, r, g, b);
}

U0 UiFillRect(F64 x, F64 y, F64 w, F64 h)
{
  cairo_rectangle(ui_cr, x, y, w, h);
  cairo_fill(ui_cr);
}

U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  cairo_set_line_width(ui_cr, 1.0);
  cairo_move_to(ui_cr, x1, y1);
  cairo_line_to(ui_cr, x2, y2);
  cairo_stroke(ui_cr);
}

UiCtl *UiMenuNew(U8 *title)
{
  if (!ui_gtk_bar) {
    ui_gtk_bar = g_menu_new;
    ui_gtk_grp = g_simple_action_group_new;
    gtk_widget_insert_action_group(ui_gtk_win, "ui", ui_gtk_grp);
    gtk_box_prepend(ui_gtk_outer, gtk_popover_menu_bar_new_from_model(ui_gtk_bar));
  }
  I64 m = g_menu_new;
  g_menu_append_submenu(ui_gtk_bar, title, m);
  return UiCtlNew(UI_MENU, m);
}

UiCtl *UiMenuItem(UiCtl *m, U8 *label, U0 *fn, U0 *data=NULL)
{
  U8 *name = MStrPrint("m%d", ++ui_gtk_nmenu);
  U8 *detailed = MStrPrint("ui.%s", name);
  UiCtl *c = UiCtlNew(UI_MENUITEM, g_simple_action_new(name, 0));
  UiOnClick(c, fn, data);
  g_signal_connect_data(c->native, "activate", &UiGtkMenuFire, c, 0, 0);
  g_action_map_add_action(ui_gtk_grp, c->native);
  g_menu_append(m->native, label, detailed);
  Free(name);
  Free(detailed);
  return c;
}

UiCtl *UiComboNew()
{
  I64 model = gtk_string_list_new(0);
  UiCtl *c = UiCtlNew(UI_COMBO, gtk_drop_down_new(model, 0));
  c->col = model;  // stash the string model to append items to
  g_signal_connect_data(c->native, "notify::selected", &UiGtkNotify, c, 0, 0);
  return c;
}

U0 UiComboAdd(UiCtl *c, U8 *text)
{
  gtk_string_list_append(c->col, text);
}

I64 UiComboSelected(UiCtl *c)
{
  I64 s = gtk_drop_down_get_selected(c->native)(I32);
  if (s == -1)  // GTK_INVALID_LIST_POSITION is 0xFFFFFFFF
    return -1;
  return s;
}

UiCtl *UiRadioNew()
{
  UiCtl *c = UiCtlNew(UI_RADIO, gtk_box_new(1, 4));
  return c;
}

U0 UiRadioAdd(UiCtl *r, U8 *text)
{
  I64 btn = gtk_check_button_new_with_label(text);
  if (r->col)  // group with the first button
    gtk_check_button_set_group(btn, r->col);
  else
    r->col = btn;
  gtk_box_append(r->native, btn);
  g_signal_connect_data(btn, "toggled", &UiGtkClicked, r, 0, 0);
  UiCtl *k = UiCtlNew(UI_BUTTON, btn);
  UiKidAdd(r, k);
}

I64 UiRadioSelected(UiCtl *r)
{
  I64 i = 0;
  UiCtl *k = r->kids;
  while (k) {
    if (gtk_check_button_get_active(k->native) & 1)
      return i;
    i++;
    k = k->sib;
  }
  return -1;
}

UiCtl *UiSpinNew(I64 min=0, I64 max=100)
{
  F64 fmin = min, fmax = max;
  UiCtl *c = UiCtlNew(UI_SPIN, gtk_spin_button_new_with_range(fmin, fmax, 1.0));
  g_signal_connect_data(c->native, "value-changed", &UiGtkClicked, c, 0, 0);
  return c;
}

I64 UiSpinValue(UiCtl *s)
{
  return gtk_spin_button_get_value_as_int(s->native)(I32);
}

UiCtl *UiMultilineNew(U8 *text="")
{
  I64 tv = gtk_text_view_new;
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(tv), text, -1);
  return UiCtlNew(UI_MULTILINE, tv);
}

UiCtl *UiPasswordNew(U8 *text="")
{
  UiCtl *c = UiCtlNew(UI_ENTRY, gtk_entry_new);
  gtk_entry_set_visibility(c->native, 0);
  gtk_editable_set_text(c->native, text);
  g_signal_connect_data(c->native, "changed", &UiGtkClicked, c, 0, 0);
  return c;
}

UiCtl *UiGroupNew(U8 *title)
{
  return UiCtlNew(UI_GROUP, gtk_frame_new(title));
}

U0 UiGroupSetChild(UiCtl *g, UiCtl *child)
{
  gtk_frame_set_child(g->native, child->native);
}

UiCtl *UiTabNew()
{
  return UiCtlNew(UI_TAB, gtk_notebook_new);
}

U0 UiTabAdd(UiCtl *t, U8 *label, UiCtl *child)
{
  gtk_notebook_append_page(t->native, child->native, gtk_label_new(label));
}

U0 UiEnable(UiCtl *c, Bool on)
{
  gtk_widget_set_sensitive(c->native, on);
}

U0 UiSetVisible(UiCtl *c, Bool on)
{
  gtk_widget_set_visible(c->native, on);
}

I64 UiGtkTimer(I64 data)
{
  UiFireClick(data);
  return 1;  // G_SOURCE_CONTINUE
}

I64 UiGtkOnce(I64 data)
{
  UiFireClick(data);
  return 0;  // G_SOURCE_REMOVE
}

U0 UiTimer(I64 ms, U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, 0);
  UiOnClick(t, fn, data);
  g_timeout_add(ms, &UiGtkTimer, t);
}

U0 UiQueueMain(U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, 0);
  UiOnClick(t, fn, data);
  g_idle_add(&UiGtkOnce, t);
}

UiCtl *UiToolbarNew()
{
  I64 box = gtk_box_new(0, 6);  // horizontal
  gtk_widget_add_css_class(box, "toolbar");
  gtk_widget_set_margin_top(box, 6);
  gtk_widget_set_margin_bottom(box, 6);
  gtk_widget_set_margin_start(box, 6);
  return UiCtlNew(UI_TOOLBAR, box);
}

U0 UiToolAdd(UiCtl *tb, U8 *label, U0 *fn, U0 *data=NULL)
{
  UiCtl *c = UiCtlNew(UI_BUTTON, gtk_button_new_with_label(label));
  UiOnClick(c, fn, data);
  g_signal_connect_data(c->native, "clicked", &UiGtkClicked, c, 0, 0);
  gtk_box_append(tb->native, c->native);
}

UiCtl *UiStatusbarNew(U8 *text="")
{
  I64 l = gtk_label_new(text);
  gtk_widget_set_margin_top(l, 4);
  gtk_widget_set_margin_bottom(l, 4);
  return UiCtlNew(UI_STATUS, l);
}

U0 UiStatusSet(UiCtl *sb, U8 *text)
{
  gtk_label_set_text(sb->native, text);
}

UiCtl *UiSplitNew(Bool vertical=FALSE)
{
  I64 p = gtk_paned_new(vertical);
  gtk_paned_set_position(p, 180);
  gtk_widget_set_vexpand(p, 1);
  return UiCtlNew(UI_SPLIT, p);
}

U0 UiSplitAdd(UiCtl *sp, UiCtl *child)
{
  if (!sp->kids) {
    gtk_paned_set_start_child(sp->native, child->native);
    UiKidAdd(sp, child);
  } else {
    gtk_paned_set_end_child(sp->native, child->native);
  }
}

UiCtl *UiScrollNew(UiCtl *child)
{
  I64 s = gtk_scrolled_window_new;
  gtk_scrolled_window_set_child(s, child->native);
  gtk_widget_set_vexpand(s, 1);
  gtk_widget_set_hexpand(s, 1);
  return UiCtlNew(UI_SCROLL, s);
}

// GTK4's native table (GtkColumnView) needs a factory/list-model dance and
// some variadic calls; a grid of labels in a scroller is variadic-free and
// fine for modest row counts. Selection is not tracked here (returns -1).
UiCtl *UiTableNew(U0 *cellfn, U0 *data=NULL)
{
  I64 grid = gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 2);
  gtk_grid_set_column_spacing(grid, 16);
  gtk_widget_set_margin_top(grid, 6);
  gtk_widget_set_margin_start(grid, 6);
  I64 s = gtk_scrolled_window_new;
  gtk_scrolled_window_set_child(s, grid);
  gtk_widget_set_vexpand(s, 1);
  UiCtl *c = UiCtlNew(UI_TABLE, s);
  c->col = grid;
  c->cellfn = cellfn;
  c->celldata = data;
  return c;
}

U0 UiTableColumn(UiCtl *t, U8 *title)
{
  I64 l = gtk_label_new(title);
  gtk_widget_add_css_class(l, "heading");
  gtk_grid_attach(t->col, l, t->w, 0, 1, 1);
  t->w++;
}

U0 UiTableSetRows(UiCtl *t, I64 nrows)
{
  I64 r = 0, c;
  t->row = nrows;
  while (r < nrows) {
    c = 0;
    while (c < t->w) {
      gtk_grid_attach(t->col, gtk_label_new(UiTableCell(t, r, c)), c, r + 1, 1, 1);
      c++;
    }
    r++;
  }
}

I64 UiTableSelected(UiCtl *t)
{
  return -1;  // grid-backed table has no row selection
}

// A real GtkTreeView backed by a GtkTreeStore. GtkTreeStore's variadic
// setters are avoided by using the *_newv / *_set_value forms. Column 0
// holds the label, column 1 the node's UiCtl* (read back on selection).
// t->col = store, t->row = tree view.
UiCtl *UiTreeNew()
{
  I64 types[2];
  types[0] = G_TYPE_STRING;
  types[1] = 68;              // G_TYPE_POINTER (17 << 2)
  I64 store = gtk_tree_store_newv(2, types);
  I64 tv = gtk_tree_view_new_with_model(store);
  gtk_tree_view_set_headers_visible(tv, 0);
  I64 col = gtk_tree_view_column_new;
  I64 rend = gtk_cell_renderer_text_new;
  gtk_tree_view_column_pack_start(col, rend, 1);
  gtk_tree_view_column_add_attribute(col, rend, "text", 0);
  gtk_tree_view_append_column(tv, col);
  I64 s = gtk_scrolled_window_new;
  gtk_scrolled_window_set_child(s, tv);
  gtk_widget_set_vexpand(s, 1);
  UiCtl *c = UiCtlNew(UI_TREE, s);
  c->col = store;
  c->row = tv;
  g_signal_connect_data(gtk_tree_view_get_selection(tv), "changed",
    &UiGtkClicked, c, 0, 0);
  return c;
}

UiCtl *UiTreeAdd(UiCtl *t, UiCtl *parent, U8 *label)
{
  UiCtl *n = UiCtlNew(UI_TREENODE, 0);
  n->celldata = StrNew(label);
  n->native = MAlloc(32);    // this node's GtkTreeIter
  I64 pit = 0;               // parent iter, NULL for a root
  if (parent)
    pit = parent->native;
  gtk_tree_store_append(t->col, n->native, pit);
  U8 gv[24];
  MemSet(gv, 0, 24);
  g_value_init(gv, G_TYPE_STRING);
  g_value_set_string(gv, label);
  gtk_tree_store_set_value(t->col, n->native, 0, gv);
  g_value_unset(gv);
  MemSet(gv, 0, 24);
  g_value_init(gv, 68);      // G_TYPE_POINTER
  g_value_set_pointer(gv, n);
  gtk_tree_store_set_value(t->col, n->native, 1, gv);
  g_value_unset(gv);
  gtk_tree_view_expand_all(t->row);
  return n;
}

UiCtl *UiTreeSelected(UiCtl *t)
{
  U8 iter[32];
  if (!gtk_tree_selection_get_selected(gtk_tree_view_get_selection(t->row),
      0, iter))
    return NULL;
  U8 gv[24];
  MemSet(gv, 0, 24);
  gtk_tree_model_get_value(t->col, iter, 1, gv);
  I64 node = g_value_get_pointer(gv);
  g_value_unset(gv);
  return node;
}

U0 UiBoxAdd(UiCtl *box, UiCtl *c)
{
  gtk_box_append(box->native, c->native);
}

U0 UiWindowSetChild(UiCtl *w, UiCtl *c)
{
  gtk_box_append(w->kids->native, c->native);
}

U0 UiGtkAlert(U8 *title, U8 *body)
{
  U8 gv[48];
  U8 *names[2];
  MemSet(gv, 0, 48);
  g_value_init(&gv[0], G_TYPE_STRING);
  g_value_set_string(&gv[0], title);
  g_value_init(&gv[24], G_TYPE_STRING);
  g_value_set_string(&gv[24], body);
  names[0] = "message";
  names[1] = "detail";
  gtk_alert_dialog_show(g_object_new_with_properties(gtk_alert_dialog_get_type,
    2, names, gv), ui_gtk_win);
}

U0 UiMsgBox(U8 *title, U8 *body)
{
  UiGtkAlert(title, body);
}

U0 UiWarnBox(U8 *title, U8 *body)
{
  U8 *t = MStrPrint("⚠ %s", title);
  UiGtkAlert(t, body);
  Free(t);
}

U0 UiGtkFileDone(I64 src, I64 res, I64 data)
{
  I64 f = gtk_file_dialog_open_finish(src, res, 0);
  ui_dlg_text = 0;
  if (f) {
    U8 *p = g_file_get_path(f);
    if (p)
      ui_dlg_text = StrNew(p);
    g_object_unref(f);
  }
  ui_dlg_done = 1;
}

U8 *UiOpenFile()
{
  ui_dlg_done = 0;
  gtk_file_dialog_open(gtk_file_dialog_new, ui_gtk_win, 0, &UiGtkFileDone, 0);
  while (!ui_dlg_done)
    g_main_context_iteration(0, 1);
  return ui_dlg_text;
}

U0 UiGtkPromptOk(I64 btn, I64 entry)
{
  ui_dlg_text = StrNew(gtk_editable_get_text(entry));
  ui_dlg_done = 1;
}

U0 UiGtkPromptGone(I64 win, I64 data)
{
  ui_dlg_gone = 1;
  ui_dlg_done = 1;
}

U8 *UiPrompt(U8 *title, U8 *body, U8 *init="")
{
  I64 win = gtk_window_new;
  gtk_window_set_title(win, title);
  gtk_window_set_modal(win, 1);
  gtk_window_set_transient_for(win, ui_gtk_win);
  I64 box = gtk_box_new(1, 10);
  gtk_widget_set_margin_top(box, 16);
  gtk_widget_set_margin_bottom(box, 16);
  gtk_widget_set_margin_start(box, 16);
  gtk_widget_set_margin_end(box, 16);
  gtk_box_append(box, gtk_label_new(body));
  I64 entry = gtk_entry_new;
  gtk_editable_set_text(entry, init);
  gtk_box_append(box, entry);
  I64 ok = gtk_button_new_with_label("OK");
  g_signal_connect_data(ok, "clicked", &UiGtkPromptOk, entry, 0, 0);
  gtk_box_append(box, ok);
  gtk_window_set_child(win, box);
  g_signal_connect_data(win, "destroy", &UiGtkPromptGone, 0, 0, 0);
  gtk_window_present(win);
  ui_dlg_done = 0;
  ui_dlg_text = 0;
  ui_dlg_gone = 0;
  while (!ui_dlg_done)
    g_main_context_iteration(0, 1);
  if (!ui_dlg_gone)
    gtk_window_destroy(win);
  return ui_dlg_text;
}

U0 UiShow(UiCtl *w)
{
  gtk_window_present(w->native);
}

U0 UiMain()
{
  ui_gtk_loop = g_main_loop_new(0, 0);
  g_main_loop_run(ui_gtk_loop);
}
