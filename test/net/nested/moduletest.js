import("./module3.http"); // loads module3 in nested, not in net
/* TODO: would be nice if these worked
window.x = new Promise(r => {
	window.r = r;
	// This works everywhere:
	eval(`import('../module5.http');`);
	// Blink fails this (but it works in FF):
	setTimeout(`import('./module3.http').then(() => r());`, 0);
});
*/
