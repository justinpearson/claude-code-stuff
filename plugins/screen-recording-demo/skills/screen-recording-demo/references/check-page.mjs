// Drives a headless Chrome over the DevTools protocol to check the tutorial section of
// easy-file-encryption.html. No dependencies: Node's built-in fetch and WebSocket.
// Usage: node check-page.mjs <url> <screenshot.png> [--expect-fallback]

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [url, shotPath, mode] = process.argv.slice(2);
const expectFallback = mode === '--expect-fallback';
const PORT = 9333 + Math.floor(Math.random() * 500);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'efe-cdp-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
	'--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
	'--no-first-run', '--no-default-browser-check', '--use-mock-keychain', '--window-size=560,900', 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
	await sleep(200);
	try {
		const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
		target = list.find((t) => t.type === 'page');
	} catch {}
}
if (!target) { chrome.kill(); throw new Error('Chrome did not start'); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let nextId = 1;
const pending = new Map();
const errors = [];
const requests = [];
ws.addEventListener('message', (ev) => {
	const msg = JSON.parse(ev.data);
	if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); return; }
	if (msg.method === 'Runtime.exceptionThrown') errors.push('exception: ' + msg.params.exceptionDetails.text);
	if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') errors.push('console.error: ' + JSON.stringify(msg.params.args.map((a) => a.value)));
	if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') errors.push('log: ' + msg.params.entry.text + ' ' + (msg.params.entry.url || ''));
	if (msg.method === 'Network.requestWillBeSent') requests.push(msg.params.request.url);
});
const send = (method, params = {}) => new Promise((resolve) => {
	const id = nextId++;
	pending.set(id, resolve);
	ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) => {
	const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
	if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.text + ' in ' + expression);
	return r.result.result.value;
};
const click = async (selector) => {
	const box = await evaluate(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return { x: r.left + 20, y: r.top + r.height / 2 }; })()`);
	for (const type of ['mousePressed', 'mouseReleased']) {
		await send('Input.dispatchMouseEvent', { type, x: box.x, y: box.y, button: 'left', clickCount: 1 });
	}
};

const results = {};
try {
	for (const domain of ['Runtime', 'Log', 'Network', 'Page']) await send(`${domain}.enable`);
	await send('Page.navigate', { url });
	await sleep(1500);

	results.requestsOnLoad = requests.filter((u) => !u.startsWith('about:')).map((u) => u.replace(/^.*\//, ''));
	results.errorsOnLoad = [...errors];
	results.summaries = await evaluate(`[...document.querySelectorAll('.howto summary')].map(s => s.textContent)`);

	await click('.howto details:nth-of-type(1) summary');
	await sleep(3000);
	results.afterOpen = await evaluate(`(() => {
		const d = document.querySelector('.howto details');
		const v = d.querySelector('video');
		const a = d.querySelector('a');
		return { open: d.open, video: v && { paused: v.paused, currentTime: +v.currentTime.toFixed(2), readyState: v.readyState, width: v.videoWidth, height: v.videoHeight, boxWidth: v.clientWidth, boxHeight: v.clientHeight }, link: a && { href: a.href, text: a.textContent } };
	})()`);
	results.videoRequests = requests.filter((u) => u.endsWith('.mp4')).map((u) => u.replace(/^.*\/videos\//, 'videos/'));

	const shot = await send('Page.captureScreenshot', { format: 'png' });
	fs.writeFileSync(shotPath, Buffer.from(shot.result.data, 'base64'));

	if (!expectFallback) {
		await click('.howto details:nth-of-type(1) summary');
		await sleep(500);
		results.afterClose = await evaluate(`(() => { const d = document.querySelector('.howto details'); return { open: d.open, paused: d.querySelector('video').paused }; })()`);
	}

	// The rest of the page still reacts to a chosen file.
	results.fileChosen = await evaluate(`(async () => {
		const input = document.getElementById('file-input');
		const dt = new DataTransfer();
		dt.items.add(new File([new Uint8Array(2048)], 'notes.zip'));
		input.files = dt.files;
		input.dispatchEvent(new Event('change'));
		await new Promise(r => setTimeout(r, 400));
		return { mode: document.getElementById('mode').textContent, button: document.getElementById('action').textContent, disabled: document.getElementById('action').disabled };
	})()`);
	results.errorsAtEnd = errors;
} finally {
	ws.close();
	chrome.kill();
	await sleep(300);
	fs.rmSync(profile, { recursive: true, force: true });
}
console.log(JSON.stringify(results, null, 1));
