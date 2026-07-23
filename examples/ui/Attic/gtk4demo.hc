// gtk4demo.hc — a real GTK4 app written in HolyC.
//
//   ./aholyc run examples/ui/gtk4demo.hc
//
// A titled window with a label and a button; the button's "clicked" signal
// and the application's "activate" signal are HolyC functions connected
// through g_signal_connect_data (the fixed-arity form behind the
// g_signal_connect macro). Closing the window ends g_application_run.
// Works against Homebrew GTK4 on macOS and system GTK4 on Linux.

// @pkgconfig=gtk4

extern I64 gtk_application_new(U8 *app_id, I64 flags);
extern I64 g_application_run(I64 app, I64 argc, I64 argv);
extern U0 g_object_unref(I64 obj);
extern I64 g_signal_connect_data(I64 obj, U8 *sig, I64 cb, I64 data,
  I64 destroy, I64 flags);
extern I64 gtk_application_window_new(I64 app);
extern U0 gtk_window_set_title(I64 win, U8 *title);
extern U0 gtk_window_set_default_size(I64 win, I64 w, I64 h);
extern U0 gtk_window_set_child(I64 win, I64 child);
extern U0 gtk_window_present(I64 win);
extern I64 gtk_box_new(I64 orientation, I64 spacing);
extern U0 gtk_box_append(I64 box, I64 child);
extern I64 gtk_label_new(U8 *text);
extern U0 gtk_label_set_text(I64 label, U8 *text);
extern I64 gtk_button_new_with_label(U8 *text);
extern U0 gtk_widget_set_margin_top(I64 w, I64 px);
extern U0 gtk_widget_set_margin_bottom(I64 w, I64 px);
extern U0 gtk_widget_set_margin_start(I64 w, I64 px);
extern U0 gtk_widget_set_margin_end(I64 w, I64 px);
extern U0 gtk_widget_set_halign(I64 w, I64 align);
extern U0 gtk_widget_set_vexpand(I64 w, I64 expand);

#define GTK_ORIENTATION_VERTICAL 1
#define GTK_ALIGN_CENTER 3

I64 gLabel, gClicks;

U0 OnClick(I64 btn, I64 data)
{
  gClicks++;
  U8 *txt = MStrPrint("Clicked %d times", gClicks);
  gtk_label_set_text(gLabel, txt);
  Free(txt);
}

U0 OnActivate(I64 app, I64 data)
{
  I64 win = gtk_application_window_new(app);
  gtk_window_set_title(win, "HolyC on GTK4");
  gtk_window_set_default_size(win, 480, 320);

  I64 box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 20);
  gtk_widget_set_margin_top(box, 20);
  gtk_widget_set_margin_bottom(box, 20);
  gtk_widget_set_margin_start(box, 20);
  gtk_widget_set_margin_end(box, 20);

  gLabel = gtk_label_new("An offering from the temple");
  gtk_widget_set_vexpand(gLabel, 1);
  gtk_box_append(box, gLabel);

  I64 btn = gtk_button_new_with_label("Click me");
  gtk_widget_set_halign(btn, GTK_ALIGN_CENTER);
  g_signal_connect_data(btn, "clicked", &OnClick, 0, 0, 0);
  gtk_box_append(box, btn);

  gtk_window_set_child(win, box);
  "gtk4demo: window up, close it to quit\n";
  gtk_window_present(win);
}

I64 app = gtk_application_new("org.aholyc.gtk4demo", 0);
g_signal_connect_data(app, "activate", &OnActivate, 0, 0, 0);
I64 rc = g_application_run(app, 0, 0);
g_object_unref(app);
Exit(rc(I32));
