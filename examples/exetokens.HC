// An #exe block sees the compiler's live token stream: class Token in
// runtime/exe.hc mirrors struct Token in src/ahc.h field for field, and
// ExeStream() returns real compiler memory -- so a block can reflect on,
// rewrite, and even consume the code that follows it.

#exe {
  Token *t = ExeStream();          // I64 magic = 21 ;
  t->next->next->next->ival *= 2;  // patch the constant in place
}
I64 magic = 21;
"magic=%d\n", magic;

// a compile-time mini-DSL: read the tokens after the block, generate
// real code from them, then eat them from the stream
#exe {
  Token *t = ExeStream();          // speed is 9 ;
  StreamPrint("I64 %s = %d;", t->str, t->next->next->ival * 100);
  ExeStreamSet(t->next->next->next->next);
}
speed is 9;
"speed=%d\n", speed;
