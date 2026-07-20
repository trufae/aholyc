/* @align */ class CAligned {
	U8 a;
	I64 b;
	U8 c;
};

/* @align=4 */ class CAlign4 {
	U8 a;
	I64 b;
	U8 c;
};

class CFieldAligned {
	U8 a;
	/* @align */ I64 b;
	U8 c;
};

U0 LocalAlignment()
{
	U8 a;
	/* @align */ I64 b;
	/* @align=16 */ I64 wide;
	&a; &b;
}

"%d %d %d %d %d %d %d %d %d\n",
	offset(CAligned.a), offset(CAligned.b), offset(CAligned.c), sizeof(CAligned),
	offset(CAlign4.b), offset(CAlign4.c), sizeof(CAlign4),
	offset(CFieldAligned.b), sizeof(CFieldAligned);
