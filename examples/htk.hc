// htk.hc — the Borland-style terminal toolkit, used natively (without the
// lib/ui wrapper): theming, tabs, frames, a bounded input field, and two
// tiled windows.  Quit with the [■] close boxes, ESC, or confirm ^C.
#include "../lib/htk/htk.hc"

// lib/term reports ^C as SIGINT; the handler runs later on HTK's event loop,
// so it can safely open this application-modal Yes/No dialog above desktop.
U0 ConfirmQuit(I64 unused)
{
  HtkConfirmQuit;
}

U0 SecondWindow(HtkCtl *from)
{
  HtkCtl *w = HtkWindowNew("Notes", 34, 10);
  HtkCtl *note = HtkMultilineNew("The temple\nis clean.\n");

  HtkMultilineSetOptions(note, HTK_MULTILINE_LINE_NUMBERS |
    HTK_MULTILINE_WRAP | HTK_MULTILINE_SCROLLBAR);
  w->low = TRUE;  // ESC dismisses
  HtkAdd(w, note);
  HtkWindowRaise(w);
  HtkSetFocus(note);
}

// Demo-only credential; real applications should validate through their own
// authentication backend instead of keeping a secret in their UI source.
#define HTK_DEMO_ACCESS_CODE "temple"

U0 AccessCodeSubmit(HtkCtl *code)
{
  if (!StrCmp(code->text, HTK_DEMO_ACCESS_CODE))
    HtkNotify("Access code accepted", 2000);
  else
    HtkNotify("Invalid access code", 2500);
}

U0 OpenNotes(HtkCtl *button)
{
  HtkCtl *code = button->data(HtkCtl *);

  if (!StrCmp(code->text, HTK_DEMO_ACCESS_CODE))
    SecondWindow(button);
  else
    HtkNotify("Invalid access code", 2500);
}

U0 HtkDemoStart(I64 unused)
{
  HtkCtl *w, *box, *tabs, *general, *about, *frame, *code, *notes;

  w = HtkWindowNew("Holy TermKit", 46, 16);
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;

  tabs = HtkTabNew;
  general = HtkNew(HTK_BOX);
  general->vertical = TRUE;
  HtkAdd(general, HtkCheckboxNew("Bless this machine", TRUE));
  code = HtkEntryNew("", 8);  // bounded: at most 8 bytes
  code->low = 20;
  code->submit = &AccessCodeSubmit;
  frame = HtkGroupNew("Access code");
  HtkAdd(frame, code);
  HtkAdd(general, frame);
  notes = HtkButtonNew("Open notes");
  notes->data = code;
  notes->changed = &OpenNotes;
  HtkAdd(general, notes);
  HtkTabAdd(tabs, "General", general);

  about = HtkNew(HTK_BOX);
  about->vertical = TRUE;
  HtkAdd(about, HtkNew(HTK_LABEL));
  HtkSetText(about->kids, "An offering,\nrendered in cells.");
  HtkTabAdd(tabs, "About", about);

  HtkAdd(box, tabs);
  HtkAdd(w, box);
  HtkSetFocus(code);  // the example starts ready for typing
}

U0 Main()
{
  if (!HtkInit) {
    "htk needs an interactive terminal\n";
    return;
  }
  // Use the named Teal preset so Settings reflects the active theme.
#ifndef HTK_NODESK
  if (!HtkSettingsSaved)
    HtkThemePreset(3);
#else
  htk_theme.desk_bg = TERM_CYAN;
  htk_theme.desk_fg = TERM_BLUE;
  htk_theme.frame = TERM_BLUE;
  htk_theme.btn_bg = TERM_MAGENTA;
  htk_theme.btn_fg = TERM_BRIGHT_WHITE;
#endif
  HtkCtrlCHandler(&ConfirmQuit, 0);
  HtkCtrlCSet(HTK_CTRLC_CALLBACK);
#ifndef HTK_NODESK
  HtkAppRegister("Terminal", &HtkTerminalWindow, 0);
  HtkAppRegister("Holy TermKit", &HtkDemoStart, 0);
#endif
  HtkDemoStart(0);
  HtkMain;
  HtkFini;
  "bye\n";
}

Main;
