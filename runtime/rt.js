// mhc HolyC runtime for JavaScript (node).
// Linear-memory model: one ArrayBuffer, pointers are byte addresses.
// I64 values are JS numbers: exact up to 53 bits (documented limitation).
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

// loads/stores (little-endian)
function lds1(a) { return DV.getInt8 (a); }
function ldu1(a) { return DV.getUint8 (a); }
function lds2(a) { return DV.getInt16 (a, true); }
function ldu2(a) { return DV.getUint16 (a, true); }
function lds4(a) { return DV.getInt32 (a, true); }
function ldu4(a) { return DV.getUint32 (a, true); }
function ld8(a) {
	const lo = DV.getUint32 (a, true), hi = DV.getInt32 (a + 4, true);
	return hi * 4294967296 + lo;
}
function ldf(a) { return DV.getFloat64 (a, true); }
function st1(a, v) { DV.setUint8 (a, v & 0xff); return v; }
function st2(a, v) { DV.setUint16 (a, v & 0xffff, true); return v; }
function st4(a, v) { DV.setUint32 (a, v >>> 0, true); return v; }
function st8(a, v) {
	v = Math.trunc (v);
	const lo = ((v % 4294967296) + 4294967296) % 4294967296;
	DV.setUint32 (a, lo, true);
	DV.setInt32 (a + 4, Math.floor (v / 4294967296), true);
	return v;
}
function stf(a, v) { DV.setFloat64 (a, v, true); return v; }

// 64-bit bitwise ops via BigInt (numbers are exact to 53 bits)
function B(v) { return BigInt (Math.trunc (v)); }
function N64(b) { return Number (BigInt.asIntN (64, b)); }
function and64(a, b) { return N64 (B (a) & B (b)); }
function or64(a, b) { return N64 (B (a) | B (b)); }
function xor64(a, b) { return N64 (B (a) ^ B (b)); }
function not64(a) { return N64 (~B (a)); }
function shl64(a, b) { return N64 (B (a) << (B (b) & 63n)); }
function ashr64(a, b) { return N64 (B (a) >> (B (b) & 63n)); }
function lshr64(a, b) { return N64 (BigInt.asUintN (64, B (a)) >> (B (b) & 63n)); }
function divi(a, b) { return Math.trunc (a / b); }
function divu(a, b) { return N64 (BigInt.asUintN (64, B (a)) / BigInt.asUintN (64, B (b))); }
function remu(a, b) { return N64 (BigInt.asUintN (64, B (a)) % BigInt.asUintN (64, B (b))); }
function ltu(a, b) { return BigInt.asUintN (64, B (a)) < BigInt.asUintN (64, B (b))? 1: 0; }
function leu(a, b) { return BigInt.asUintN (64, B (a)) <= BigInt.asUintN (64, B (b))? 1: 0; }
function wrap8(v) { return (v & 0xff) << 24 >> 24; }
function wrapu8(v) { return v & 0xff; }
function wrap16(v) { return (v & 0xffff) << 16 >> 16; }
function wrapu16(v) { return v & 0xffff; }
function wrap32(v) { return v | 0; }
function wrapu32(v) { return v >>> 0; }

// data segment init
function D(addr, bytes) {
	U8A.set (bytes, addr);
}

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
function wstr(a, s) {
	for (let i = 0; i < s.length; i++) {
		U8A[a + i] = s.charCodeAt (i) & 0xff;
	}
	U8A[a + s.length] = 0;
}
function chstr(v) {
	let s = "", u = BigInt.asUintN (64, B (v));
	while (u && s.length < 8) {
		s += String.fromCharCode (Number (u & 0xffn));
		u >>= 8n;
	}
	return s;
}

// output
function W(s) {
	process.stdout.write (Buffer.from (s, "latin1"));
}

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

// ------------------------------------------------------------- exceptions
function hcThrow(ch) {
	st8 (TASK, ch);
	st8 (TASK + 8, 0);
	throw HCEXC;
}
function PutExcept(catch_it) {
	W ("Except:" + chstr (ld8 (TASK)) + "\n");
	st8 (TASK + 8, catch_it);
}

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
function CAlloc(size) {
	const p = MAlloc (size);
	U8A.fill (0, p, p + size);
	return p;
}
function Free(p) { /* bump allocator: no-op */ }
function MSize(p) { return p? ld8 (p - 16): 0; }
function MemCpy(d, s, n) {
	U8A.copyWithin (d, s, s + n);
	return d;
}
function MemSet(d, v, n) {
	U8A.fill (v & 0xff, d, d + n);
	return d;
}
function MemCmp(a, b, n) {
	for (let i = 0; i < n; i++) {
		if (U8A[a + i] !== U8A[b + i]) {
			return U8A[a + i] - U8A[b + i];
		}
	}
	return 0;
}

// ---------------------------------------------------------------- strings
function StrLen(s) { return cstr (s).length; }
function StrCpy(d, s) { wstr (d, cstr (s)); return d; }
function StrCat(d, s) { wstr (d + cstr (d).length, cstr (s)); return d; }
function StrCmp(a, b) {
	const x = cstr (a), y = cstr (b);
	return x < y? -1: x > y? 1: 0;
}
function StrNew(s) {
	const j = cstr (s);
	const p = MAlloc (j.length + 1);
	wstr (p, j);
	return p;
}

// ------------------------------------------------------------- formatting
function u64s(v, radix) {
	return BigInt.asUintN (64, B (v)).toString (radix);
}
function efmt(d, prec) {
	let s = d.toExponential (prec);
	return s.replace (/e([+-])(\d)$/, "e$10$2");
}
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
function Print(fmt, argc, argv) {
	W (hcFormat (fmt, argc, argv));
}
function StrPrint(dst, fmt, argc, argv) {
	wstr (dst, hcFormat (fmt, argc, argv));
	return dst;
}
function MStrPrint(fmt, argc, argv) {
	const s = hcFormat (fmt, argc, argv);
	const p = MAlloc (s.length + 1);
	wstr (p, s);
	return p;
}
function PutChars(ch) { W (chstr (ch)); }
function PutS(s) { W (cstr (s)); }

// --------------------------------------------------------------------- io
let hcStdin = null, hcStdinPos = 0;
function hcReadStdin() {
	if (hcStdin === null) {
		try {
			hcStdin = require ("fs").readFileSync (0, "latin1");
		} catch (e) {
			hcStdin = "";
		}
	}
}
function GetChar() {
	hcReadStdin ();
	if (hcStdinPos >= hcStdin.length) {
		return -1;
	}
	return hcStdin.charCodeAt (hcStdinPos++) & 0xff;
}
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

// ------------------------------------------------------------------- math
function __hc_pow(a, b) { return Math.pow (a, b); }
function Sqrt(x) { return Math.sqrt (x); }
function Sin(x) { return Math.sin (x); }
function Cos(x) { return Math.cos (x); }
function Tan(x) { return Math.tan (x); }
function ASin(x) { return Math.asin (x); }
function ACos(x) { return Math.acos (x); }
function ATan(x) { return Math.atan (x); }
function Exp(x) { return Math.exp (x); }
function Ln(x) { return Math.log (x); }
function Log10(x) { return Math.log10 (x); }
function Log2(x) { return Math.log2 (x); }
function Ceil(x) { return Math.ceil (x); }
function Floor(x) { return Math.floor (x); }
function Abs(x) { return Math.abs (x); }
function AbsI64(x) { return x < 0? -x: x; }
function Round(x) { return Math.round (x); }
function ToI64(x) { return Math.trunc (x); }
function ToF64(x) { return x; }
function ToBool(x) { return x !== 0? 1: 0; }
function MinI64(a, b) { return a < b? a: b; }
function MaxI64(a, b) { return a > b? a: b; }
let hcSeed = 0x5deece66d;
function Seed(s) { hcSeed = Math.trunc (s); }
function RandI64() {
	hcSeed = N64 (BigInt.asUintN (64, B (hcSeed) * 6364136223846793005n + 1442695040888963407n));
	return Math.abs (Math.trunc (hcSeed / 2));
}
function Rand() {
	return (RandI64 () % 9007199254740992) / 9007199254740992;
}
function Exit(code) { process.exit (code); }
function hcThrowFn(ch) { hcThrow (ch); } // 'throw' is reserved in JS
