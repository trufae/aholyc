// An ordinary helper compiled before #exe can generate global declarations.
// TempleOS uses the live compiler symbol table; aholyc recompiles the source
// prefix into the temporary #exe DSO.

class CPair
{
  I64 x;
  I64 y;
};

U0 DefineBox(U8 *name, U8 *type)
{
  StreamPrint("class %s { %s value; };", name, type);
  StreamPrint("U0 %sSet(%s *box, %s *value) { box->value = *value; }",
    name, name, type);
}

U0 GeneratedStatement()
{
  #exe {
    StreamPrint("\"inside function\\n\";");
  };
}

// This is runtime startup code. Recompiling the prefix for #exe must not run it.
"runtime once\n";

#exe {
  DefineBox("CPairBox", "CPair");
  DefineBox("I64Box", "I64");
};

CPairBox pair_box;
I64Box number_box;
CPair pair;
I64 number;

pair.x = 20;
pair.y = 22;
number = 42;
GeneratedStatement;
CPairBoxSet(&pair_box, &pair);
I64BoxSet(&number_box, &number);
"pair=%d,%d number=%d\n",
  pair_box.value.x, pair_box.value.y, number_box.value;
