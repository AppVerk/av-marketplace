// miro-frames.js - writing to a Miro board from a background tab (av-dev).
//
// The board page (https://miro.com/app/board/<id>/) exposes window.miro.board
// (Miro Web SDK). Reads (get, getById, getInfo) work in an inactive tab.
// Writes (create*, sync, remove) wait for requestAnimationFrame, and Chrome does
// not fire rAF in a hidden tab: the promise hangs forever. withFrames replaces
// rAF for the duration of one operation with a MessageChannel pump (~60 frames/s),
// then restores the original. Outside the operation the background tab uses no CPU.
//
// av-setup copies this file into the repo (<paths.scripts>/miro-frames.js);
// description in <docs.root>/miro.md.
// Usage: paste this file at the start of the code in javascript_tool
// (claude-in-chrome), then:
//   await withFrames(async () => { item.content = '...'; await item.sync(); });
// A 'TIMEOUT' result after limitMs means the write did not go through; read the
// element again and check its state before you retry.
// Do not use setTimeout for limits: in a hidden tab Chrome throttles timers
// (down to 1 call per minute), and the tool ends after 45 s.

async function withFrames(fn, limitMs = 20000) {
  const origR = window.requestAnimationFrame;
  const origC = window.cancelAnimationFrame;
  const queue = new Map();
  let nextId = 1e9;
  let active = true;
  let last = 0;
  const pump = new MessageChannel();
  pump.port1.onmessage = () => {
    if (!active) return;
    const now = performance.now();
    if (now - last >= 16 && queue.size) {
      last = now;
      const callbacks = [...queue.values()];
      queue.clear();
      for (const cb of callbacks) {
        try { cb(now); } catch (e) { console.error('[av-miro]', e); }
      }
    }
    pump.port2.postMessage(0);
  };
  window.requestAnimationFrame = cb => { const id = ++nextId; queue.set(id, cb); return id; };
  window.cancelAnimationFrame = id => { queue.delete(id); origC.call(window, id); };
  pump.port2.postMessage(0);
  const start = performance.now();
  const limit = new Promise(resolve => {
    const clock = new MessageChannel();
    clock.port1.onmessage = () => {
      if (!active) return;
      if (performance.now() - start > limitMs) resolve('TIMEOUT');
      else clock.port2.postMessage(0);
    };
    clock.port2.postMessage(0);
  });
  try {
    return await Promise.race([fn(), limit]);
  } finally {
    active = false;
    window.requestAnimationFrame = origR;
    window.cancelAnimationFrame = origC;
  }
}

async function boardReady(limitMs = 30000) {
  const start = performance.now();
  while (window.boardLoading || !(window.miro && window.miro.board)) {
    if (performance.now() - start > limitMs) return false;
    await new Promise(resolve => { const c = new MessageChannel(); c.port1.onmessage = resolve; c.port2.postMessage(0); });
  }
  return true;
}
