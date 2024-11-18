function assert(x, msg) {
	const mymsg = msg ? ": " + msg : "";
	if (!x)
		throw new TypeError("Assertion failed" + mymsg);
}

function assertThrows(expr, error) {
	let me;
	try {
		eval(expr);
	} catch (e) {
		if (e instanceof error)
			return;
		me = e;
	}
	throw new TypeError("Assertion failed: expected " + error + ", got " + me + " for expression: " + expr);
}

function assertEquals(a, b) {
	assert(a === b, "Expected " + b + " but got " + a);
}

function assertNotEquals(a, b) {
	assert(a !== b, "Expected " + b + " to have some different value");
}

function assertInstanceof(a, b) {
	assert(a instanceof b, a + " not an instance of " + b);
}
