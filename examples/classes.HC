// Classes with single inheritance, exactly like TempleOS.
class CAnimal
{
  I64 age;
  I64 legs;
};

class CDog : CAnimal
{
  U8 name[32];
};

U0 Describe(CDog *d)
{
  "%s: %d legs, age %d\n", d->name, d->legs, d->age;
}

CDog *d = MAlloc(sizeof(CDog));
MemCpy(d->name, "Rex", 4);
d->age = 3;
d->legs = 4;
Describe(d);

// class values on the stack work too
CDog pup;
MemCpy(pup.name, "Pup", 4);
pup.age = 1;
pup.legs = 4;
Describe(&pup);

"sizeof(CAnimal)=%d offset(CDog.name)=%d\n", sizeof(CAnimal), offset(CDog.name);
Free(d);
