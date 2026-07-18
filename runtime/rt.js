// aholyc HolyC runtime for JavaScript (node).
// Linear-memory model: one ArrayBuffer, pointers are byte addresses.
// I64 values are JS numbers: exact up to 53 bits (documented limitation).
//
// '//@ name dep...' markers split this file into chunks: the JS backend
// only emits the chunks the compiled program actually uses (plus this
// leading core chunk, which is always included).
"use strict";
const MEM = new ArrayBuffer(64 << 20);
const DV = new DataView(MEM);
const U8A = new Uint8Array(MEM);
const TASK = 16;          // CTask { except_ch, catch_except }
const EXT = { Fs: 32 };   // extern globals: address of the cell
let FP = 0, ASP = 0, HP = 0, HEAP_END = MEM.byteLength;
const HCEXC = { holyc: true };

function setLayout(dataEnd) {
	let a = (dataEnd + 4095) & ~4095;
	FP = a;                 // stack frames: 8 MB
	a += 8 << 20;
	ASP = a;                // vararg slots: 1 MB
	a += 1 << 20;
	HP = a;                 // heap: the rest
	st8 (EXT.Fs, TASK);
}

function ld8(a) {
	const lo = DV.getUint32 (a, true), hi = DV.getInt32 (a + 4, true);
	return hi * 4294967296 + lo;
}
function st8(a, v) {
	v = Math.trunc (v);
	const lo = ((v % 4294967296) + 4294967296) % 4294967296;
	DV.setUint32 (a, lo, true);
	DV.setInt32 (a + 4, Math.floor (v / 4294967296), true);
	return v;
}

// data segment init
function D(addr, bytes) {
	U8A.set (bytes, addr);
}

//@ lds1
function lds1(a) { return DV.getInt8 (a); }
//@ ldu1
function ldu1(a) { return DV.getUint8 (a); }
//@ lds2
function lds2(a) { return DV.getInt16 (a, true); }
//@ ldu2
function ldu2(a) { return DV.getUint16 (a, true); }
//@ lds4
function lds4(a) { return DV.getInt32 (a, true); }
//@ ldu4
function ldu4(a) { return DV.getUint32 (a, true); }
//@ ldf
function ldf(a) { return DV.getFloat64 (a, true); }
//@ st1
function st1(a, v) { DV.setUint8 (a, v & 0xff); return v; }
//@ st2
function st2(a, v) { DV.setUint16 (a, v & 0xffff, true); return v; }
//@ st4
function st4(a, v) { DV.setUint32 (a, v >>> 0, true); return v; }
//@ stf
function stf(a, v) { DV.setFloat64 (a, v, true); return v; }

//@ B
// 64-bit bitwise ops via BigInt (numbers are exact to 53 bits)
function B(v) { return BigInt (Math.trunc (v)); }
//@ N64
function N64(b) { return Number (BigInt.asIntN (64, b)); }
//@ and64 B N64
function and64(a, b) { return N64 (B (a) & B (b)); }
//@ or64 B N64
function or64(a, b) { return N64 (B (a) | B (b)); }
//@ xor64 B N64
function xor64(a, b) { return N64 (B (a) ^ B (b)); }
//@ not64 B N64
function not64(a) { return N64 (~B (a)); }
//@ shl64 B N64
function shl64(a, b) { return N64 (B (a) << (B (b) & 63n)); }
//@ ashr64 B N64
function ashr64(a, b) { return N64 (B (a) >> (B (b) & 63n)); }
//@ lshr64 B N64
function lshr64(a, b) { return N64 (BigInt.asUintN (64, B (a)) >> (B (b) & 63n)); }
//@ divi
function divi(a, b) { return Math.trunc (a / b); }
//@ divu B N64
function divu(a, b) { return N64 (BigInt.asUintN (64, B (a)) / BigInt.asUintN (64, B (b))); }
//@ remu B N64
function remu(a, b) { return N64 (BigInt.asUintN (64, B (a)) % BigInt.asUintN (64, B (b))); }
//@ ltu B
function ltu(a, b) { return BigInt.asUintN (64, B (a)) < BigInt.asUintN (64, B (b))? 1: 0; }
//@ leu B
function leu(a, b) { return BigInt.asUintN (64, B (a)) <= BigInt.asUintN (64, B (b))? 1: 0; }
//@ wrap8
function wrap8(v) { return (v & 0xff) << 24 >> 24; }
//@ wrapu8
function wrapu8(v) { return v & 0xff; }
//@ wrap16
function wrap16(v) { return (v & 0xffff) << 16 >> 16; }
//@ wrapu16
function wrapu16(v) { return v & 0xffff; }
//@ wrap32
function wrap32(v) { return v | 0; }
//@ wrapu32
function wrapu32(v) { return v >>> 0; }

//@ cstr
// strings
function cstr(a) {
	if (!a) {
		return "";
	}
	let e = a;
	while (U8A[e]) {
		e++;
	}
	return Buffer.from (U8A.subarray (a, e)).toString ("latin1");
}
//@ wstr
function wstr(a, s) {
	for (let i = 0; i < s.length; i++) {
		U8A[a + i] = s.charCodeAt (i) & 0xff;
	}
	U8A[a + s.length] = 0;
}
//@ chstr B
function chstr(v) {
	let s = "", u = BigInt.asUintN (64, B (v));
	while (u && s.length < 8) {
		s += String.fromCharCode (Number (u & 0xffn));
		u >>= 8n;
	}
	return s;
}

//@ W
// output
function W(s) {
	process.stdout.write (Buffer.from (s, "latin1"));
}

//@ hcVCall stf st8
// variadic call helper: extras go into the arg stack as 8-byte slots
function hcVCall(fn, fixed, extras, ff) {
	const base = ASP;
	for (let i = 0; i < extras.length; i++) {
		if (ff[i]) {
			stf (base + 8 * i, extras[i]);
		} else {
			st8 (base + 8 * i, extras[i]);
		}
	}
	ASP += extras.length * 8;
	try {
		return fn (...fixed, extras.length, base);
	} finally {
		ASP = base;
	}
}

//@ hcThrow st8
// ------------------------------------------------------------- exceptions
function hcThrow(ch) {
	st8 (TASK, ch);
	st8 (TASK + 8, 0);
	throw HCEXC;
}
//@ hcThrowFn hcThrow
function hcThrowFn(ch) { hcThrow (ch); } // 'throw' is reserved in JS
//@ PutExcept W chstr st8
function PutExcept(catch_it) {
	W ("Except:" + chstr (ld8 (TASK)) + "\n");
	st8 (TASK + 8, catch_it);
}

//@ __hc_rip
// '$$' outside a class body. JS has no code addresses; hand out distinct
// monotonic fake ones so pointer-style comparisons still behave.
let hcRip = 0x400000;
function __hc_rip() { return hcRip += 16; }

//@ MAlloc st8 hcThrow
// ----------------------------------------------------------------- memory
function MAlloc(size) {
	if (size < 0) {
		size = 0;
	}
	const p = (HP + 15) & ~15;
	HP = p + 16 + size;
	if (HP > HEAP_END) {
		hcThrow (0x4d454d4f4e); // 'NOMEM'
	}
	st8 (p, size);
	return p + 16;
}
//@ CAlloc MAlloc
function CAlloc(size) {
	const p = MAlloc (size);
	U8A.fill (0, p, p + size);
	return p;
}
//@ Free
function Free(p) { /* bump allocator: no-op */ }
//@ MSize
function MSize(p) { return p? ld8 (p - 16): 0; }
//@ MemCpy
function MemCpy(d, s, n) {
	U8A.copyWithin (d, s, s + n);
	return d;
}
//@ MemSet
function MemSet(d, v, n) {
	U8A.fill (v & 0xff, d, d + n);
	return d;
}
//@ MemCmp
function MemCmp(a, b, n) {
	for (let i = 0; i < n; i++) {
		if (U8A[a + i] !== U8A[b + i]) {
			return U8A[a + i] - U8A[b + i];
		}
	}
	return 0;
}

//@ StrLen cstr
// ---------------------------------------------------------------- strings
function StrLen(s) { return cstr (s).length; }
//@ StrCpy wstr cstr
function StrCpy(d, s) { wstr (d, cstr (s)); return d; }
//@ StrCat wstr cstr
function StrCat(d, s) { wstr (d + cstr (d).length, cstr (s)); return d; }
//@ StrCmp cstr
function StrCmp(a, b) {
	const x = cstr (a), y = cstr (b);
	return x < y? -1: x > y? 1: 0;
}
//@ StrNew cstr MAlloc wstr
function StrNew(s) {
	const j = cstr (s);
	const p = MAlloc (j.length + 1);
	wstr (p, j);
	return p;
}

//@ u64s B
// ------------------------------------------------------------- formatting
function u64s(v, radix) {
	return BigInt.asUintN (64, B (v)).toString (radix);
}
//@ efmt
function efmt(d, prec) {
	let s = d.toExponential (prec);
	return s.replace (/e([+-])(\d)$/, "e$10$2");
}
//@ gfmt efmt
function gfmt(d, prec) {
	let p = prec || 6;
	if (p === 0) {
		p = 1;
	}
	if (d === 0) {
		return "0";
	}
	const e = Math.floor (Math.log10 (Math.abs (d)));
	let s;
	if (e < -4 || e >= p) {
		s = efmt (d, p - 1);
		s = s.replace (/\.?0+e/, "e");
	} else {
		s = d.toFixed (Math.max (0, p - 1 - e));
		if (s.indexOf (".") >= 0) {
			s = s.replace (/\.?0+$/, "");
		}
	}
	return s;
}
//@ hcFormat cstr u64s efmt gfmt chstr ldf
function hcFormat(fmtAddr, argc, argvAddr) {
	const f = cstr (fmtAddr);
	let out = "", ai = 0;
	for (let i = 0; i < f.length; i++) {
		if (f[i] !== "%") {
			out += f[i];
			continue;
		}
		i++;
		if (f[i] === "%") {
			out += "%";
			continue;
		}
		let left = false, zero = false;
		while (f[i] === "-" || f[i] === "0" || f[i] === "+" || f[i] === " ") {
			if (f[i] === "-") {
				left = true;
			}
			if (f[i] === "0") {
				zero = true;
			}
			i++;
		}
		let width = 0;
		while (f[i] >= "0" && f[i] <= "9") {
			width = width * 10 + (f.charCodeAt (i++) - 48);
		}
		let prec = -1;
		if (f[i] === ".") {
			i++;
			prec = 0;
			while (f[i] >= "0" && f[i] <= "9") {
				prec = prec * 10 + (f.charCodeAt (i++) - 48);
			}
		}
		const slot = ai < argc? argvAddr + 8 * ai: 0;
		ai++;
		const iv = slot? ld8 (slot): 0;
		const dv = slot? ldf (slot): 0;
		let s;
		switch (f[i]) {
		case "d": case "i": s = String (iv); break;
		case "u": s = u64s (iv, 10); break;
		case "x": s = u64s (iv, 16); break;
		case "X": s = u64s (iv, 16).toUpperCase (); break;
		case "o": s = u64s (iv, 8); break;
		case "p": case "P":
			s = u64s (iv, 16).toUpperCase ().padStart (16, "0");
			break;
		case "c": s = chstr (iv); break;
		case "s":
			s = cstr (iv);
			if (prec >= 0) {
				s = s.slice (0, prec);
			}
			break;
		case "f": s = dv.toFixed (prec < 0? 6: prec); break;
		case "e": s = efmt (dv, prec < 0? 6: prec); break;
		case "g": s = gfmt (dv, prec < 0? 6: prec); break;
		default: s = "%" + f[i]; break;
		}
		if (s.length < width) {
			if (left) {
				s = s.padEnd (width, " ");
			} else {
				s = s.padStart (width, zero? "0": " ");
			}
		}
		out += s;
	}
	return out;
}
//@ Print W hcFormat
function Print(fmt, argc, argv) {
	W (hcFormat (fmt, argc, argv));
}
//@ StrPrint wstr hcFormat
function StrPrint(dst, fmt, argc, argv) {
	wstr (dst, hcFormat (fmt, argc, argv));
	return dst;
}
//@ MStrPrint MAlloc wstr hcFormat
function MStrPrint(fmt, argc, argv) {
	const s = hcFormat (fmt, argc, argv);
	const p = MAlloc (s.length + 1);
	wstr (p, s);
	return p;
}
//@ StrPrintJoin hcFormat cstr MAlloc wstr Free
function StrPrintJoin(dst, fmt, argc, argv) {
	const s = (dst? cstr (dst): "") + hcFormat (fmt, argc, argv);
	Free (dst);
	const p = MAlloc (s.length + 1);
	wstr (p, s);
	return p;
}
//@ PutChars W chstr
function PutChars(ch) { W (chstr (ch)); }
//@ PutS W cstr
function PutS(s) { W (cstr (s)); }

//@ hcStdinState
// --------------------------------------------------------------------- io
let hcStdin = null, hcStdinPos = 0;
//@ hcReadStdin hcStdinState
function hcReadStdin() {
	if (hcStdin === null) {
		try {
			hcStdin = require ("fs").readFileSync (0, "latin1");
		} catch (e) {
			hcStdin = "";
		}
	}
}
//@ GetChar hcReadStdin
function GetChar() {
	hcReadStdin ();
	if (hcStdinPos >= hcStdin.length) {
		return -1;
	}
	return hcStdin.charCodeAt (hcStdinPos++) & 0xff;
}
//@ GetStr W cstr hcReadStdin MAlloc wstr
function GetStr(prompt) {
	if (prompt) {
		W (cstr (prompt));
	}
	hcReadStdin ();
	let e = hcStdin.indexOf ("\n", hcStdinPos);
	if (e < 0) {
		e = hcStdin.length;
	}
	const s = hcStdin.slice (hcStdinPos, e);
	hcStdinPos = e + 1;
	const p = MAlloc (s.length + 1);
	wstr (p, s);
	return p;
}

//@ hcBitA
// ------------------------------------------------------------------- bits
// byte address / mask of a signed bit offset, like x86 BT
function hcBitA(p, bit) { return p + Math.floor (bit / 8); }
//@ hcBitM
function hcBitM(bit) { return 1 << (((bit % 8) + 8) % 8); }
//@ Bsf B
function Bsf(v) {
	let u = BigInt.asUintN (64, B (v));
	if (!u) {
		return -1;
	}
	let i = 0;
	while (!(u & 1n)) {
		u >>= 1n;
		i++;
	}
	return i;
}
//@ Bsr B
function Bsr(v) {
	let u = BigInt.asUintN (64, B (v)), i = -1;
	while (u) {
		u >>= 1n;
		i++;
	}
	return i;
}
//@ BCnt B
function BCnt(v) {
	let u = BigInt.asUintN (64, B (v)), n = 0;
	while (u) {
		n += Number (u & 1n);
		u >>= 1n;
	}
	return n;
}
//@ Bt hcBitA hcBitM
function Bt(p, bit) {
	return U8A[hcBitA (p, bit)] & hcBitM (bit)? 1: 0;
}
//@ Btc hcBitA hcBitM
function Btc(p, bit) {
	const a = hcBitA (p, bit), m = hcBitM (bit);
	const r = U8A[a] & m? 1: 0;
	U8A[a] ^= m;
	return r;
}
//@ Btr hcBitA hcBitM
function Btr(p, bit) {
	const a = hcBitA (p, bit), m = hcBitM (bit);
	const r = U8A[a] & m? 1: 0;
	U8A[a] &= ~m;
	return r;
}
//@ Bts hcBitA hcBitM
function Bts(p, bit) {
	const a = hcBitA (p, bit), m = hcBitM (bit);
	const r = U8A[a] & m? 1: 0;
	U8A[a] |= m;
	return r;
}
//@ BEqu Bts Btr
function BEqu(p, bit, val) { return val? Bts (p, bit): Btr (p, bit); }
//@ LBtc Btc
const LBtc = Btc; // node is single-threaded: locked == plain
//@ LBtr Btr
const LBtr = Btr;
//@ LBts Bts
const LBts = Bts;
//@ LBEqu BEqu
const LBEqu = BEqu;

//@ __hc_pow
// ------------------------------------------------------------------- math
function __hc_pow(a, b) { return Math.pow (a, b); }
//@ Sqrt
function Sqrt(x) { return Math.sqrt (x); }
//@ Sin
function Sin(x) { return Math.sin (x); }
//@ Cos
function Cos(x) { return Math.cos (x); }
//@ Tan
function Tan(x) { return Math.tan (x); }
//@ ASin
function ASin(x) { return Math.asin (x); }
//@ ACos
function ACos(x) { return Math.acos (x); }
//@ ATan
function ATan(x) { return Math.atan (x); }
//@ Exp
function Exp(x) { return Math.exp (x); }
//@ Ln
function Ln(x) { return Math.log (x); }
//@ Log10
function Log10(x) { return Math.log10 (x); }
//@ Log2
function Log2(x) { return Math.log2 (x); }
//@ Ceil
function Ceil(x) { return Math.ceil (x); }
//@ Floor
function Floor(x) { return Math.floor (x); }
//@ Abs
function Abs(x) { return Math.abs (x); }
//@ AbsI64
function AbsI64(x) { return x < 0? -x: x; }
//@ Round
function Round(x) { return Math.round (x); }
//@ ToI64
function ToI64(x) { return Math.trunc (x); }
//@ ToF64
function ToF64(x) { return x; }
//@ ToBool
function ToBool(x) { return x !== 0? 1: 0; }
//@ MinI64
function MinI64(a, b) { return a < b? a: b; }
//@ MaxI64
function MaxI64(a, b) { return a > b? a: b; }
//@ hcSeedState
let hcSeed = 0x5deece66d;
//@ Seed hcSeedState
function Seed(s) { hcSeed = Math.trunc (s); }
//@ RandI64 hcSeedState N64 B
function RandI64() {
	hcSeed = N64 (BigInt.asUintN (64, B (hcSeed) * 6364136223846793005n + 1442695040888963407n));
	return Math.abs (Math.trunc (hcSeed / 2));
}
//@ Rand RandI64
function Rand() {
	return (RandI64 () % 9007199254740992) / 9007199254740992;
}
//@ Exit
function Exit(code) { process.exit (code); }
