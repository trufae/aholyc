// Classic m68k AmigaOS 3.x ABI. Native pointers are U32 fields, not HolyC
// pointers. Tests compare these layouts with the installed NDK headers.
class UiAmigaTag { U32 tag, value; };
class UiAmigaWindow
{
  $$ = 8; I16 width, height;
  $$ = 46; U32 screen, port;
  I8 left, top, right, bottom;
  $$ = 86; U32 messages;
};
class UiAmigaScreen { $$ = 40; U32 font; $$ = 48; U32 colors; };
class UiAmigaPort { $$ = 15; U8 signal; };
class UiAmigaMessage
{
  $$ = 20; U32 event;
  U16 code, qualifier;
  U32 address;
  I16 x, y;
};
class UiAmigaGadget
{
  $$ = 12; U16 flags;
  $$ = 34; U32 special;
  U16 id; U32 user;
};
class UiAmigaString { U32 buffer; $$ = 28; I32 number; };
class UiAmigaNewGadget
{
  I16 x, y, w, h;
  U32 text, font;
  U16 id;
  U32 flags, visual, user;
};
class UiAmigaNewMenu
{
  U8 type, pad;
  U32 label, key;
  U16 flags;
  I32 exclude;
  U32 user;
};
class UiAmigaMenuItem { $$ = 32; U16 next; U32 user; };
class UiAmigaEasy { U32 size, flags, title, body, buttons; };
class UiAmigaFile { $$ = 4; U32 file, drawer; };
class UiAmigaList { U32 head, tail, previous; U8 type, pad; };
class UiAmigaNode
{
  U32 next, previous;
  U8 type; I8 priority;
  U32 name;
  // The fields above are an Exec Node; the rest belong to the backend.
  U8 *text;
  UiCtl *control;
};

extern U32 IntuitionBase, GfxBase, GadToolsBase, AslBase;
extern U8 *OpenLibrary(U8 *name, U32 version);
extern U0 CloseLibrary(U0 *base);
extern U32 Wait(U32 signals);
extern U8 *OpenWindowTagList(U0 *window, UiAmigaTag *tags);
extern U0 CloseWindow(U0 *window);
extern U0 CurrentTime(U32 *seconds, U32 *micros);
extern U16 AddGList(U0 *window, U0 *gadgets, U32 position, I32 count, U0 *requester);
extern U16 RemoveGList(U0 *window, U0 *gadgets, I32 count);
extern U0 RefreshGList(U0 *gadgets, U0 *window, U0 *requester, I32 count);
extern U8 *CreateContext(U32 *list);
extern U8 *CreateGadgetA(U32 kind, U0 *previous, UiAmigaNewGadget *g, UiAmigaTag *tags);
extern U0 FreeGadgets(U0 *gadgets);
extern U0 GT_SetGadgetAttrsA(U0 *gadget, U0 *window, U0 *requester, UiAmigaTag *tags);
extern U8 *GT_GetIMsg(U0 *port);
extern U0 GT_ReplyIMsg(U0 *message);
extern U0 GT_RefreshWindow(U0 *window, U0 *requester);
extern U0 GT_BeginRefresh(U0 *window);
extern U0 GT_EndRefresh(U0 *window, I32 complete);
extern U8 *GetVisualInfoA(U0 *screen, UiAmigaTag *tags);
extern U0 FreeVisualInfo(U0 *visual);
extern U8 *CreateMenusA(UiAmigaNewMenu *menus, UiAmigaTag *tags);
extern I32 LayoutMenusA(U0 *menus, U0 *visual, UiAmigaTag *tags);
extern I32 SetMenuStrip(U0 *window, U0 *menus);
extern U0 ClearMenuStrip(U0 *window);
extern U0 FreeMenus(U0 *menus);
extern U8 *ItemAddress(U0 *menus, U32 number);
extern U0 DrawBevelBoxA(U0 *port, I32 x, I32 y, I32 w, I32 h, UiAmigaTag *tags);
extern U0 SetAPen(U0 *port, U32 pen);
extern U0 SetDrMd(U0 *port, U32 mode);
extern U0 RectFill(U0 *port, I32 x1, I32 y1, I32 x2, I32 y2);
extern U0 Move(U0 *port, I32 x, I32 y);
extern U0 Draw(U0 *port, I32 x, I32 y);
extern U0 Text(U0 *port, U8 *text, U32 length);
extern I32 FindColor(U0 *colors, U32 r, U32 g, U32 b, I32 limit);
extern I32 EasyRequestArgs(U0 *window, UiAmigaEasy *request, U32 *idcmp, U0 *args);
extern U8 *AllocAslRequest(U32 kind, UiAmigaTag *tags);
extern I32 AslRequest(U0 *request, UiAmigaTag *tags);
extern U0 FreeAslRequest(U0 *request);

#define UA_WA 0x80000063
#define UA_GT 0x80080000
#define UA_DISABLED 0x8003000E
#define UA_RESIZE 2
#define UA_REFRESH 4
#define UA_BUTTONS 8
#define UA_MOTION 16
#define UA_DOWN 32
#define UA_UP 64
#define UA_MENU 256
#define UA_CLOSE 512
#define UA_TICK 0x400000
