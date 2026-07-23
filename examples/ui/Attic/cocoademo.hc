// cocoademo.hc — a real Cocoa app written in HolyC.
//
//   ./aholyc run examples/ui/cocoademo.hc
//
// @ldflags=-framework AppKit -lobjc

extern I64 dlsym(I64 handle, U8 *name);
extern I64 objc_getClass(U8 *name);
extern I64 sel_registerName(U8 *name);
extern I64 objc_allocateClassPair(I64 super, U8 *name, I64 extra);
extern U0 objc_registerClassPair(I64 cls);
extern I64 class_addMethod(I64 cls, I64 sel, I64 imp, U8 *types);

#define RTLD_DEFAULT (-2)
#define NS_STYLE_TITLED_CLOSABLE_MINI_RESIZE 15
#define NS_BACKING_BUFFERED 2

// one objc_msgSend per call shape: ints/pointers, and leading-NSRect
I64 (*msg)(I64 self, I64 sel, I64 a, I64 b, I64 c);
I64 (*msgR)(I64 self, I64 sel, F64 x, F64 y, F64 w, F64 h, I64 a, I64 b, I64 c);

I64 gLabel, gClicks;

I64 S(U8 *name) { return sel_registerName(name); }
I64 Cls(U8 *name) { return objc_getClass(name); }
I64 NSStr(U8 *s) { return msg(Cls("NSString"), S("stringWithUTF8String:"), s, 0, 0); }

// IMP for HCTarget clicked: — a plain HolyC function
U0 OnClick(I64 self, I64 cmd, I64 sender)
{
  gClicks++;
  U8 *txt = MStrPrint("Clicked %d times", gClicks);
  msg(gLabel, S("setStringValue:"), NSStr(txt), 0, 0);
  Free(txt);
}

// IMP for the app delegate: quit when the last window closes
I64 QuitOnClose(I64 self, I64 cmd, I64 sender) { return 1; }

msg  = dlsym(RTLD_DEFAULT, "objc_msgSend");
msgR = dlsym(RTLD_DEFAULT, "objc_msgSend");

msg(msg(Cls("NSAutoreleasePool"), S("alloc"), 0, 0, 0), S("init"), 0, 0, 0);
I64 app = msg(Cls("NSApplication"), S("sharedApplication"), 0, 0, 0);
msg(app, S("setActivationPolicy:"), 0, 0, 0);   // regular app: Dock icon, key windows

// app delegate class, built at runtime with a HolyC IMP
I64 dcls = objc_allocateClassPair(Cls("NSObject"), "HCDelegate", 0);
class_addMethod(dcls, S("applicationShouldTerminateAfterLastWindowClosed:"),
  &QuitOnClose, "c@:@");
objc_registerClassPair(dcls);
msg(app, S("setDelegate:"), msg(msg(dcls, S("alloc"), 0, 0, 0), S("init"), 0, 0, 0), 0, 0);

// button target class
I64 tcls = objc_allocateClassPair(Cls("NSObject"), "HCTarget", 0);
class_addMethod(tcls, S("clicked:"), &OnClick, "v@:@");
objc_registerClassPair(tcls);
I64 target = msg(msg(tcls, S("alloc"), 0, 0, 0), S("init"), 0, 0, 0);

// window
// rect args MUST be F64 literals: typed fn-ptr param types are not converted,
// and AppKit reads the NSRect from the float registers
I64 win = msgR(msg(Cls("NSWindow"), S("alloc"), 0, 0, 0),
  S("initWithContentRect:styleMask:backing:defer:"),
  0.0, 0.0, 480.0, 320.0, NS_STYLE_TITLED_CLOSABLE_MINI_RESIZE, NS_BACKING_BUFFERED, 0);
msg(win, S("setTitle:"), NSStr("HolyC on Cocoa"), 0, 0);
msg(win, S("center"), 0, 0, 0);
I64 cv = msg(win, S("contentView"), 0, 0, 0);

// label + button
gLabel = msg(Cls("NSTextField"), S("labelWithString:"),
  NSStr("An offering from the temple"), 0, 0);
msgR(gLabel, S("setFrame:"), 20.0, 270.0, 440.0, 24.0, 0, 0, 0);
msg(cv, S("addSubview:"), gLabel, 0, 0);

I64 btn = msg(Cls("NSButton"), S("buttonWithTitle:target:action:"),
  NSStr("Click me"), target, S("clicked:"));
msgR(btn, S("setFrame:"), 180.0, 140.0, 120.0, 32.0, 0, 0, 0);
msg(cv, S("addSubview:"), btn, 0, 0);

"cocoademo: window up, close it to quit\n";
msg(win, S("makeKeyAndOrderFront:"), 0, 0, 0);
msg(app, S("activateIgnoringOtherApps:"), 1, 0, 0);
msg(app, S("run"), 0, 0, 0);
