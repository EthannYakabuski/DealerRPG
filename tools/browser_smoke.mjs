/** Isolated Chrome smoke driver. Requires Node 22+; no packages or personal profile. */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, openSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const local = path.join(project, '.local');
const output = path.join(project, 'build', 'screenshots');
const logs = path.join(project, 'build', 'logs');
const sessionPath = path.join(local, 'browser-qa-session.json');
const args = process.argv.slice(2);
const action = args[0] || 'boot';
const option = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index < 0 ? fallback : args[index + 1];
};
const validateGameUrl = value => {
  const url = new URL(value);
  const localHost = ['127.0.0.1', 'localhost'].includes(url.hostname) && ['http:', 'https:'].includes(url.protocol);
  const publishedGame = url.href === 'https://ethannyakabuski.github.io/DealerRPG/';
  if (url.username || url.password || (!localHost && !publishedGame)) throw new Error('Only localhost or the exact DealerRPG Pages URL is allowed.');
  return url.href;
};
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
for (const directory of [local, output, logs]) mkdirSync(directory, { recursive: true });
if (typeof WebSocket !== 'function' || typeof fetch !== 'function') {
  throw new Error('Use Node 22 or newer for built-in WebSocket and fetch support.');
}

class Protocol {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 0;
    this.requests = new Map();
    this.events = [];
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const request = this.requests.get(message.id);
        if (!request) return;
        clearTimeout(request.timer);
        this.requests.delete(message.id);
        if (message.error) request.reject(new Error(JSON.stringify(message.error)));
        else request.resolve(message.result);
      } else if (message.method) this.events.push(message);
    });
    socket.addEventListener('close', () => {
      for (const request of this.requests.values()) {
        clearTimeout(request.timer);
        // Chrome can close its debugging socket before acknowledging shutdown.
        if (request.method === 'Browser.close') request.resolve({});
        else request.reject(new Error(`QA browser disconnected during ${request.method}`));
      }
      this.requests.clear();
    });
  }
  send(method, params = {}, sessionId) {
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.requests.delete(id);
        reject(new Error(`Browser command timed out: ${method}`));
      }, 20000);
      this.requests.set(id, { resolve, reject, timer, method });
      this.socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
}

async function connect(url) {
  const parsed = new URL(url);
  if (!['127.0.0.1', 'localhost'].includes(parsed.hostname)) throw new Error('Only local debugging endpoints are allowed.');
  const socket = new WebSocket(url);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  return new Protocol(socket);
}

let session;
if (action === 'boot') {
  const gameUrl = validateGameUrl(option('url', 'http://127.0.0.1:8060/'));
  const chrome = process.env.CHROME_EXE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  if (!existsSync(chrome)) throw new Error('Set CHROME_EXE to an installed Chrome executable.');
  const profile = path.join(local, 'chrome-qa-profile', String(Date.now()));
  mkdirSync(profile, { recursive: true });
  const browserLog = openSync(path.join(logs, 'browser-process.log'), 'a');
  const processHandle = spawn(chrome, [
    '--headless=new', '--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
    `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    '--window-size=1280,800', '--force-device-scale-factor=1', 'about:blank',
  ], { detached: true, windowsHide: true, stdio: ['ignore', browserLog, browserLog] });
  processHandle.unref();
  const portFile = path.join(profile, 'DevToolsActivePort');
  const deadline = Date.now() + 20000;
  while (!existsSync(portFile) && Date.now() < deadline) await pause(100);
  if (!existsSync(portFile)) throw new Error('Chrome did not expose its isolated debugging endpoint.');
  const [port, endpoint] = readFileSync(portFile, 'utf8').trim().split(/\r?\n/);
  session = { browserUrl: `ws://127.0.0.1:${port}${endpoint}`, profile, pid: processHandle.pid, url: gameUrl };
} else {
  session = JSON.parse(readFileSync(sessionPath, 'utf8'));
  if (!session.profile.startsWith(path.join(local, 'chrome-qa-profile') + path.sep)) throw new Error('Refusing to control a non-QA profile.');
  validateGameUrl(session.url);
}

const protocol = await connect(session.browserUrl);
let attached;
let failed = false;
try {
  if (action === 'close') {
    await protocol.send('Browser.close');
    console.log('Closed the isolated QA browser.');
  } else {
    if (action === 'boot') {
      const created = await protocol.send('Target.createTarget', { url: 'about:blank' });
      session.targetId = created.targetId;
      writeFileSync(sessionPath, JSON.stringify(session, null, 2));
    }
    attached = (await protocol.send('Target.attachToTarget', { targetId: session.targetId, flatten: true })).sessionId;
    const send = (method, params) => protocol.send(method, params, attached);
    await send('Runtime.enable');
    await send('Log.enable');
    await send('Page.enable');
    await send('Network.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: Number(option('width', 1280)), height: Number(option('height', 800)), deviceScaleFactor: 1, mobile: false });
    let benchmark = null;
    if (action === 'boot' || action === 'reload') {
      if (action === 'boot') await send('Page.navigate', { url: session.url });
      else await send('Page.reload', { ignoreCache: true });
      const deadline = Date.now() + 90000;
      let ready = false;
      while (Date.now() < deadline) {
        const state = await send('Runtime.evaluate', {
          expression: 'JSON.stringify({ready: !!document.getElementById("canvas") && !document.getElementById("loading"), error: document.getElementById("notice")?.hidden === false ? document.getElementById("notice").textContent : null})', returnByValue: true,
        });
        if (state.result.value) {
          const status = JSON.parse(state.result.value);
          if (status.error) throw new Error(status.error);
          if (status.ready) { ready = true; break; }
        }
        await pause(250);
      }
      if (!ready) throw new Error('Game did not finish WebAssembly startup within 90 seconds.');
      await pause(1000);
    } else if (action === 'click') {
      const x = Number(option('x', NaN));
      const y = Number(option('y', NaN));
      if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error('Click requires --x and --y from the observed screenshot.');
      await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
      await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
      await pause(400);
    } else if (action === 'key') {
      const key = option('key', 'b');
      const special = { Tab: ['Tab', 9], Escape: ['Escape', 27], ' ': ['Space', 32], Enter: ['Enter', 13] };
      const [code, number] = special[key] || [`Key${key.toUpperCase()}`, key.toUpperCase().charCodeAt(0)];
      const fields = { key, code, windowsVirtualKeyCode: number, nativeVirtualKeyCode: number };
      await send('Input.dispatchKeyEvent', { type: 'keyDown', ...fields });
      await pause(Math.min(2000, Math.max(30, Number(option('hold', 80)))));
      await send('Input.dispatchKeyEvent', { type: 'keyUp', ...fields });
      await pause(400);
    } else if (action === 'pad') {
      // Exercise Godot's exported Gamepad API path without requiring a physical
      // controller on the runner. This applies only to this isolated QA tab.
      const button = Number(option('button', -1));
      const axis = Number(option('axis', -1));
      const value = Number(option('value', 1));
      const hold = Math.min(2000, Math.max(60, Number(option('hold', 140))));
      if (!Number.isInteger(button) || button < -1 || button > 16 || !Number.isInteger(axis) || axis < -1 || axis > 3 || !Number.isFinite(value) || Math.abs(value) > 1) throw new Error('Pad expects a standard button 0–16 or axis 0–3 and value -1 to 1.');
      const result = await send('Runtime.evaluate', { expression: `(() => {
        if (!window.__nightSchoolQaPad) {
          const pad = { id: 'QA Standard Gamepad', index: 0, connected: true, mapping: 'standard', axes: [0,0,0,0], buttons: Array.from({length:17},()=>({pressed:false,touched:false,value:0})) };
          window.__nightSchoolQaPad = pad;
          Object.defineProperty(navigator, 'getGamepads', { configurable:true, value:()=>[pad] });
          const event = new Event('gamepadconnected');
          Object.defineProperty(event,'gamepad',{value:pad});
          window.dispatchEvent(event);
        }
        const pad = window.__nightSchoolQaPad;
        if (${button} >= 0) pad.buttons[${button}] = {pressed:true,touched:true,value:1};
        if (${axis} >= 0) pad.axes[${axis}] = ${value};
        return true;
      })()`, returnByValue:true });
      if (result.exceptionDetails) throw new Error('Virtual gamepad could not be connected.');
      await pause(hold);
      await send('Runtime.evaluate', { expression: 'window.__nightSchoolQaPad.buttons.forEach(b=>{b.pressed=false;b.touched=false;b.value=0}); window.__nightSchoolQaPad.axes.fill(0);' });
      await pause(400);
    } else if (action === 'benchmark') {
      const measurement = await send('Runtime.evaluate', {
        expression: `new Promise(resolve => {
          const intervals = [];
          let first = 0, previous = 0;
          const sample = now => {
            if (!first) first = now;
            if (previous) intervals.push(now - previous);
            previous = now;
            if (now - first < 5000) { requestAnimationFrame(sample); return; }
            const sorted = [...intervals].sort((a, b) => a - b);
            const average = intervals.reduce((sum, value) => sum + value, 0) / intervals.length;
            const gl = document.getElementById('canvas').getContext('webgl2');
            const debug = gl && gl.getExtension('WEBGL_debug_renderer_info');
            resolve({
              durationMs: now - first, frames: intervals.length,
              averageFps: 1000 / average,
              p50FrameMs: sorted[Math.floor((sorted.length - 1) * 0.5)],
              p95FrameMs: sorted[Math.floor((sorted.length - 1) * 0.95)],
              renderer: gl ? gl.getParameter(debug ? debug.UNMASKED_RENDERER_WEBGL : gl.RENDERER) : null,
              webglVersion: gl ? gl.getParameter(gl.VERSION) : null,
              note: 'Browser animation-frame timing for the currently visible scene; this does not measure individual game subsystems.'
            });
          };
          requestAnimationFrame(sample);
        })`,
        awaitPromise: true, returnByValue: true,
      });
      benchmark = measurement.result.value;
      if (!benchmark || measurement.exceptionDetails) throw new Error('Browser frame benchmark failed.');
    } else if (action !== 'capture') throw new Error(`Unknown browser test action: ${action}`);

    const screenshot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    const name = path.basename(option('name', `browser-${action}`)).replace(/[^a-zA-Z0-9_-]/g, '_');
    const screenshotPath = path.join(output, `${name}.png`);
    writeFileSync(screenshotPath, Buffer.from(screenshot.data, 'base64'));
    const consoleMessages = protocol.events.filter(event => event.method === 'Runtime.consoleAPICalled').map(event => ({
      level: event.params.type,
      text: event.params.args.map(argument => argument.value ?? argument.description ?? '').join(' '),
    }));
    const exceptions = protocol.events.filter(event => event.method === 'Runtime.exceptionThrown').map(event => event.params.exceptionDetails);
    const networkFailures = protocol.events.filter(event => event.method === 'Network.loadingFailed').map(event => event.params);
    const seriousMessages = consoleMessages.filter(item => item.level === 'error' || /SCRIPT ERROR:|^ERROR:/m.test(item.text));
    failed = exceptions.length > 0 || seriousMessages.length > 0;
    const report = { action, screenshot: screenshotPath, url: session.url, consoleMessages, exceptions, networkFailures, benchmark, passed: !failed };
    const reportPath = path.join(logs, `${name}.json`);
    writeFileSync(reportPath, JSON.stringify(report, null, 2));
    appendFileSync(path.join(logs, 'browser-actions.log'), `${new Date().toISOString()} ${action} ${failed ? 'FAIL' : 'PASS'} ${name}\n`);
    console.log(JSON.stringify({ passed: !failed, screenshot: screenshotPath, report: reportPath, consoleErrors: seriousMessages.length, exceptions: exceptions.length, networkFailures: networkFailures.length, ...(benchmark ? { benchmark } : {}) }));
  }
} catch (error) {
  failed = true;
  writeFileSync(path.join(logs, 'browser-smoke-failure.json'), JSON.stringify({ message: error.message, events: protocol.events }, null, 2));
  console.error(error.message);
} finally {
  protocol.socket.close();
}
process.exitCode = failed ? 1 : 0;
