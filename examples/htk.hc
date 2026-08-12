// htk.hc — the Borland-style terminal toolkit, used natively (without the
// lib/ui wrapper): theming, tabs, frames, a bounded input field, and two
// tiled windows.  Quit with the [■] close boxes, ESC, or ^C.
#include "../lib/htk/htk.hc"

U0 SecondWindow(HtkCtl *from)
{
  HtkCtl *w = HtkWindowNew("Notes", 34, 10);
  HtkCtl *note = HtkMultilineNew("The temple\nis clean.\n");

  w->low = TRUE;  // ESC dismisses
  HtkAdd(w, note);
}

U0 Main()
{
  HtkCtl *w, *box, *tabs, *general, *about, *frame, *code;

  if (!HtkInit) {
    "htk needs an interactive terminal\n";
    return;
  }
  // Retheme: teal desktop, yellow accents on the frames.
  htk_theme.desk_bg = TERM_CYAN;
  htk_theme.desk_fg = TERM_BLUE;
  htk_theme.frame = TERM_BRIGHT_YELLOW;
  htk_theme.btn_bg = TERM_MAGENTA;
  htk_theme.btn_fg = TERM_BRIGHT_WHITE;

  w = HtkWindowNew("Holy TermKit", 46, 16);
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;

  tabs = HtkTabNew;
  general = HtkNew(HTK_BOX);
  general->vertical = TRUE;
  HtkAdd(general, HtkCheckboxNew("Bless this machine", TRUE));
  code = HtkEntryNew("", 8);  // bounded: at most 8 bytes
  code->low = 20;
  frame = HtkGroupNew("Access code");
  HtkAdd(frame, code);
  HtkAdd(general, frame);
  HtkAdd(general, HtkButtonNew("Open notes"));
  general->kids->sib->sib->changed = &SecondWindow;
  HtkTabAdd(tabs, "General", general);

  about = HtkNew(HTK_BOX);
  about->vertical = TRUE;
  HtkAdd(about, HtkNew(HTK_LABEL));
  HtkSetText(about->kids, "An offering,\nrendered in cells.");
  HtkTabAdd(tabs, "About", about);

  HtkAdd(box, tabs);
  HtkAdd(w, box);
  HtkMain;
  HtkFini;
  "bye\n";
}

Main;
