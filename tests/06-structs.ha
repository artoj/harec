use rt::{compile, exited, EXIT_SUCCESS};

fn padding() void = {
	assert(size(struct { x: i32, y: i32 }) == 8);
	assert(size(struct { x: i32, y: i64 }) == 16);
	assert(size(union { x: i8, y: i16, z: i32 }) == 4);
	assert(align(struct { x: i32, y: i32 }) == 4);
	assert(align(struct { x: i32, y: i64 }) == 8);
	assert(align(union { x: i8, y: i16, z: i32 }) == 4);

	const s = struct {
		x: i8 = 10,
		y: i16 = 20,
		z: i32 = 30,
		q: i64 = 40,
	};
	assert(&s.x: uintptr: size % 1 == 0);
	assert(&s.y: uintptr: size % 2 == 0);
	assert(&s.z: uintptr: size % 4 == 0);
	assert(&s.q: uintptr: size % 8 == 0);
};

fn storage() void = {
	let coords = struct { x: i32 = 10, y: i32 = 20 };
	let ptr = &coords: *[*]i32;
	assert(ptr[0] == 10 && ptr[1] == 20);
};

fn assignment() void = {
	let coords = struct { x: int = 20, y: int = 30 };
	coords.x = 40;
	coords.y = 50;
	assert(coords.x == 40 && coords.y == 50);
	coords = struct { x: int = 60, y: int = 70 };
	assert(coords.x == 60 && coords.y == 70);
};

fn deref() void = {
	let coords = struct { x: int = 20, y: int = 30 };
	let a = &coords;
	assert(a.x == 20 && a.y == 30);
	let b = &a;
	assert(b.x == 20 && b.y == 30);
	let c = &b;
	assert(c.x == 20 && c.y == 30);
	c.x = 42;
	c.y = 96;
	assert(coords.x == 42 && coords.y == 96);
};

type embedded = struct {
	foo: u8,
};

type embed1 = struct {
	embedded,
	struct {
		bar: u8,
		baz: u64,
	},
};

type embed2 = struct {
	struct {
		bar: u8,
		baz: u64,
	},
	embedded,
};

fn nested() void = {
	let s = embed1 {
		foo = 42,
		bar = 69,
		baz = 1337,
	};
	assert(offset(s.foo) == 0 && offset(s.bar) == 8 && offset(s.baz) == 16);
	assert(s.foo == 42 && s.bar == 69 && s.baz == 1337);
	let s = embed2 {
		foo = 42,
		bar = 69,
		baz = 1337,
	};
	assert(offset(s.bar) == 0 && offset(s.baz) == 8 && offset(s.foo) == 16);
	assert(s.foo == 42 && s.bar == 69 && s.baz == 1337);

	let s = struct {
		x: int = 10,
		y: struct {
			z: int,
			q: int,
			a: struct { b: int, c: int },
		} = struct {
			z: int = 20,
			q: int = 30,
			a: struct { b: int, c: int } = struct {
				b: int = 42, c: int = 24,
			},
		},
	};
	assert(s.x == 10);
	assert(s.y.z == 20);
	assert(s.y.q == 30);
	assert(s.y.a.b == 42);
	assert(s.y.a.c == 24);
	assert(&s.y: uintptr == &s.y.z: uintptr);

	s.x = 1337;
	assert(s.x == 1337);

	s.y.a = struct { b: int = 1337, c: int = 7331 };
	assert(s.y.a.b == 1337);
	assert(s.y.a.c == 7331);
};

type coords = struct { x: int, y: int };

type coords3 = struct { coords, z: int };
type embed = struct { a: uint, b: u8 };
// complex embedded hierarchy
type me = struct { embed, coords3, f: int, g: (int, str) };
let g1: me = me {        b = 4, x = -1, y = -2, z = -3, f = 20, ... };
let g2: me = me {               x = -1, y = -2, z = -3, f = 20, ... };
let g3: me = me {                       y = -2, z = -3, f = 20, ... };
let g4: me = me {                               z = -3, f = 20, ... };
let g5: me = me {                                       f = 20, ... };
let g6: me = me {                                               ... };

fn named() void = {
	let x = coords { y = 10, x = 20 };
	assert(x.x == 20 && x.y == 10);
};

fn autofill() void = {
	let x = coords { x = 10, ... };
	assert(x.x == 10 && x.y == 0);

	assert(g1.a == 0 && g1.b == 4 && g1.x == -1 && g1.y == -2 && g1.z == -3 && g1.f == 20 && g1.g.0 == 0 && g1.g.1 == "");
	assert(g2.a == 0 && g2.b == 0 && g2.x == -1 && g2.y == -2 && g2.z == -3 && g2.f == 20 && g2.g.0 == 0 && g2.g.1 == "");
	assert(g3.a == 0 && g3.b == 0 && g3.x == 0  && g3.y == -2 && g3.z == -3 && g3.f == 20 && g3.g.0 == 0 && g3.g.1 == "");
	assert(g4.a == 0 && g4.b == 0 && g4.x == 0  && g4.y == 0  && g4.z == -3 && g4.f == 20 && g4.g.0 == 0 && g4.g.1 == "");
	assert(g5.a == 0 && g5.b == 0 && g5.x == 0  && g5.y == 0  && g5.z == 0  && g5.f == 20 && g5.g.0 == 0 && g5.g.1 == "");
	assert(g6.a == 0 && g6.b == 0 && g6.x == 0  && g6.y == 0  && g6.z == 0  && g6.f == 0  && g6.g.0 == 0 && g6.g.1 == "");

	let l1: me = me {        b = 4, x = -1, y = -2, z = -3, f = 20, ... };
	let l2: me = me {               x = -1, y = -2, z = -3, f = 20, ... };
	let l3: me = me {                       y = -2, z = -3, f = 20, ... };
	let l4: me = me {                               z = -3, f = 20, ... };
	let l5: me = me {                                       f = 20, ... };
	let l6: me = me {                                               ... };

	assert(l1.a == 0 && l1.b == 4 && l1.x == -1 && l1.y == -2 && l1.z == -3 && l1.f == 20 && l1.g.0 == 0 && l1.g.1 == "");
	assert(l2.a == 0 && l2.b == 0 && l2.x == -1 && l2.y == -2 && l2.z == -3 && l2.f == 20 && l2.g.0 == 0 && l2.g.1 == "");
	assert(l3.a == 0 && l3.b == 0 && l3.x == 0  && l3.y == -2 && l3.z == -3 && l3.f == 20 && l3.g.0 == 0 && l3.g.1 == "");
	assert(l4.a == 0 && l4.b == 0 && l4.x == 0  && l4.y == 0  && l4.z == -3 && l4.f == 20 && l4.g.0 == 0 && l4.g.1 == "");
	assert(l5.a == 0 && l5.b == 0 && l5.x == 0  && l5.y == 0  && l5.z == 0  && l5.f == 20 && l5.g.0 == 0 && l5.g.1 == "");
	assert(l6.a == 0 && l6.b == 0 && l6.x == 0  && l6.y == 0  && l6.z == 0  && l6.f == 0  && l6.g.0 == 0 && l6.g.1 == "");
};

fn invariants() void = {
	const failures = [
	// Assign field from non-assignable type:
	"fn test() void = { let x: struct { y: int } = struct { y: int = 10u }; };",

	"
	type coords = struct { x: int, y: int };

	fn test() void = {
		let x = coords { x: int = 10u, y: int = 20u };
	};
	",

	// multiple initializations for single field
	"type s = struct { x: int }; fn test() s = s { x = 5, x = 7 };",

	"type e = struct { x: int }, s = struct { y: int, e };"
	"fn test() s = s { x = 5, x = 7 };",

	"type e = struct { x: int }, s = struct { e, y: int};"
	"fn test() s = s { x = 5, x = 7 };",

	// Duplicate members
	"fn test() void = { let x: struct { a: int, a: int } = struct { a: int = 2 };"
	// Dereference non-nullable pointer:
	"fn test() void = { let x: nullable *struct { y: int } = null; x.y; };",
	// Select field from non-struct object:
	"fn test() void = { let x = 10; x.y; };",
	// Unknown field:
	"fn test() void = { let x: struct { y: int } = struct { y: int = 10 }; x.z; };",
	// Untyped field for unnamed struct:
	"fn test() void = { let x = struct { x = 10 }; };",
	// Members of undefined size before last
	"type s = struct { x: [*]int, a: str };",
	// Members of size 0
	"type s = struct { x: void, a: str };"
	];
	for (let i = 0z; i < len(failures); i += 1) {
		assert(compile(failures[i]) as exited != EXIT_SUCCESS);
	};
};

fn fields() void = {
	let n: u32 = 0;

	let up = &n: *union {
		struct {
			a: u8,
			b: u8,
		},
		c: u32,
	};
	assert(&up.a: uintptr == &n: uintptr);
	assert(&up.b: uintptr == &n: uintptr + 1);
	assert(&up.c: uintptr == &n: uintptr);

	let sp  = &n: *struct {
		a: u8,
		struct {
			b: u8,
			struct {
				c: u8,
			},
		},
	};
	assert(&sp.a: uintptr == &n: uintptr);
	assert(&sp.b: uintptr == &n: uintptr + 1);
	assert(&sp.c: uintptr == &n: uintptr + 2);
};

def S = struct {
	a: u8 = 69,
	b: u32 = 1337,
};

fn eval() void = {
	static let s = struct {
		a: u8 = 69,
		b: u32 = 1337,
	};

	static assert(S.a == 69);

	static assert(struct {
		a: u8 = 69,
		b: u32 = 1337,
	}.b == 1337);
};

export fn main() void = {
	padding();
	storage();
	assignment();
	deref();
	nested();
	named();
	autofill();
	invariants();
	fields();
	eval();
	// TODO:
	// - Union tests
	// - Embedded structs
	// - offset()
};
