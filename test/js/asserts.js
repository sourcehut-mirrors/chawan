function assert(x, msg) {
	const mymsg = msg ? ": " + msg : "";
	if (!x)
		throw new TypeError("Assertion failed" + mymsg);
}

function assertThrows(expr, error) {
	try {
		eval(expr);
	} catch (e) {
		if (e instanceof Error)
			return;
	}
	throw new TypeError("Assertion failed");
}

function assertEquals(a, b) {
	assert(a === b, "Expected " + b + " but got " + a);
}

function assertInstanceof(a, b) {
	assert(a instanceof b, a + " not an instance of " + b);
}
