// miro-frames.js - zapis na tablicy Miro z karty w tle (av-dev).
//
// Strona tablicy (https://miro.com/app/board/<id>/) wystawia window.miro.board
// (Web SDK Miro). Odczyt (get, getById, getInfo) dziala na nieaktywnej karcie.
// Zapis (create*, sync, remove) czeka na requestAnimationFrame, a Chrome nie
// odpala rAF na ukrytej karcie: obietnica wisi bez konca. withFrames podmienia
// rAF na czas jednej operacji na pompe MessageChannel (~60 klatek/s), potem
// przywraca oryginal. Poza operacja karta w tle nie zuzywa CPU.
//
// Plik trafia do repo przez av-setup (<paths.scripts>/miro-frames.js); opis w
// <docs.root>/miro.md.
// Uzycie: wklej ten plik na poczatek kodu w javascript_tool (claude-in-chrome),
// potem:
//   await withFrames(async () => { item.content = '...'; await item.sync(); });
// Wynik 'TIMEOUT' po limitMs znaczy, ze zapis nie przeszedl; odczytaj element
// jeszcze raz i sprawdz stan, zanim powtorzysz.
// Nie uzywaj setTimeout do limitow: na ukrytej karcie Chrome dlawi timery
// (do 1 wywolania na minute), a narzedzie konczy sie po 45 s.

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
