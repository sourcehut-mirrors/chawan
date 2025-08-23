function assert(x, msg) {
	const mymsg = msg ? ": " + msg : "";
	if (!x)
		throw new TypeError("Assertion failed" + mymsg);
}

function assertThrows(fun, error) {
	if (!(fun instanceof Function))
		throw new TypeError("error expected to be Function");
	let me;
	try {
		fun();
	} catch (e) {
		if (e instanceof error)
			return;
		me = e;
	}
	throw new TypeError("Assertion failed: expected " + error + ", got " + me + " for: " + fun);
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
