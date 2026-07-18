// lastclass: the default becomes the previous argument's class name
// as a string, with pointer levels stripped (see TempleOS Demo/LastClass.HC).
U0 StructName(U8 *d, U8 *class_name=lastclass)
{
  "it is a \"%s\".\n", class_name;
}

class Student
{
  Student *next;
  I64 age;
  U8 name[32];
};

class School
{
  U8 name[32];
  Student *students;
};

Student a;
School s;
I64 i;
F64 f;

StructName(&a);
StructName(&s);
StructName(&i);
StructName(&f);
StructName(&a, "override");
