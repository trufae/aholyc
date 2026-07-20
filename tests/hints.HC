class HintBox {
	/* @bits=3 */ U8 member;
	/* @bits=1 */ I8 signed_bit;
};

#define U1 /* @bits=1 */ U8

/* @bits=1 */ U8 global_bit = 2;
/* @bits=64 */ U64 full_width = 1;

/* @inline */ I64 InlineAdd(I64 x) { return x + 1; }
/* @noinline */ I64 NoInlineAdd(I64 x) { return x + 2; }

U0 ShowHints(/* @bits=4 */ I8 param)
{
	/* @bits=4 */ I8 signed_nibble = 15;
	/* @bits=4 */ U8 unsigned_nibble = 15;
	// @bits=1
	I8 signed_bit = 3;
	/* @bits=3 */ U8 addressed = 15;
	U1 macro_bit = 1;
	U8 *address = &addressed;
	*address = 14;
	HintBox box;
	box.member = 7;
	I64 compound_member = box.member += 1;
	I64 post_member = box.member++;
	box.signed_bit = 1;
	I64 signed_member = box.signed_bit += 2;
	"%d %d %d %d %d %d %d %d %d %d %d\n", global_bit, signed_nibble,
		unsigned_nibble, param, addressed, compound_member, post_member,
		box.member, signed_bit, signed_member, macro_bit;
}

ShowHints(15);
