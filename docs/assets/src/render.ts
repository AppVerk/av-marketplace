#!/usr/bin/env bun
/**
 * Renders the README diagrams: docs/assets/src/<name>.html -> docs/assets/<name>.png.
 *
 *   bun docs/assets/src/render.ts [<name> ...]     no names: every *.html in docs/assets/src
 *
 * CHROME      Chrome or Chromium binary (default: macOS Google Chrome, then google-chrome,
 *             google-chrome-stable, chromium, chromium-browser on PATH)
 * RENDER_OUT  output directory (default: docs/assets)
 *
 * Each page declares <meta name="render-size" content="WxH"> and may declare
 * <meta name="render-scale" content="1"> (default 2). A page fails, and nothing is written for it,
 * when a bundled font does not load, a .card or .box overflows, its text uses a glyph outside the
 * bundled Latin subset, or its wires were not drawn.
 */
import { spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative, resolve, sep } from "node:path";
import { Readable, Writable } from "node:stream";

const SRC = import.meta.dir;
const OUT = resolve(process.env.RENDER_OUT ?? join(SRC, ".."));
const CHECK = `(async () => {
  const probes = ['400 20px "Space Grotesk"', '700 20px "Space Grotesk"', '400 20px "JetBrains Mono"', '600 20px "JetBrains Mono"'];
  const loaded = await Promise.all(probes.map((p) => document.fonts.load(p).then((faces) => faces.length > 0, () => false)));
  await document.fonts.ready;
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const errors = probes.filter((_, i) => !loaded[i]).map((p) => "font not loaded: " + p);
  for (const el of document.querySelectorAll(".card, .box")) {
    if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1)
      errors.push(\`overflow: \${el.id || el.className} (\${el.scrollWidth}x\${el.scrollHeight} in \${el.clientWidth}x\${el.clientHeight})\`);
  }
  const bad = [...new Set([...document.body.innerText].filter((ch) => {
    const c = ch.codePointAt(0);
    return !(c === 9 || c === 10 || (c >= 0x20 && c <= 0x7e) || (c >= 0xa0 && c <= 0xff) || (c >= 0x2000 && c <= 0x206f));
  }))];
  if (bad.length) errors.push("glyphs outside the bundled font subset: " + bad.map((ch) => "U+" + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")).join(", "));
  if (document.body.dataset.wireError) errors.push("wire error: " + document.body.dataset.wireError);
  else if (document.querySelector("svg.wires") && !document.body.dataset.wires) errors.push("wires not drawn");
  return errors;
})()`;

interface Diagram {
  name: string;
  width: number;
  height: number;
  scale: number;
}

interface CdpResult {
  targetId?: string;
  sessionId?: string;
  errorText?: string;
  exceptionDetails?: { text: string };
  result?: { value?: string[] };
  data?: string;
}

interface CdpMessage {
  id?: number;
  result?: CdpResult;
  error?: { message: string };
  method?: string;
  sessionId?: string;
}

interface PendingCommand {
  method: string;
  resolve: (result: CdpResult) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

interface PendingEvent {
  event: string;
  sessionId: string;
  resolve: () => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

class Cdp {
  private nextId = 0;
  private commands = new Map<number, PendingCommand>();
  private events: PendingEvent[] = [];
  private closed = false;

  constructor(private toChrome: Writable, fromChrome: Readable) {
    let input = "";
    fromChrome.setEncoding("utf8");
    fromChrome.on("data", (chunk: string): void => {
      input += chunk;
      let start = 0;
      for (let end = input.indexOf("\0"); end !== -1; end = input.indexOf("\0", start)) {
        const message: CdpMessage = JSON.parse(input.slice(start, end));
        this.receive(message);
        start = end + 1;
      }
      input = input.slice(start);
    });
    fromChrome.once("end", (): void => this.close(new Error("connection closed")));
    fromChrome.once("close", (): void => this.close(new Error("connection closed")));
    toChrome.once("close", (): void => this.close(new Error("connection closed")));
    fromChrome.on("error", (error: Error): void => this.close(error));
    toChrome.on("error", (error: Error): void => this.close(error));
  }

  private receive(message: CdpMessage): void {
    if (message.id !== undefined) {
      const pending = this.commands.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.commands.delete(message.id);
      if (message.error) pending.reject(new Error(`CDP ${pending.method}: ${message.error.message}`));
      else pending.resolve(message.result ?? {});
    } else {
      this.events = this.events.filter((pending: PendingEvent): boolean => {
        if (pending.event !== message.method || pending.sessionId !== message.sessionId) return true;
        clearTimeout(pending.timeout);
        pending.resolve();
        return false;
      });
    }
  }

  close(error: Error): void {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.commands.values()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error(`CDP ${pending.method}: ${error.message}`));
    }
    this.commands.clear();
    for (const pending of this.events) {
      clearTimeout(pending.timeout);
      pending.reject(new Error(`CDP ${pending.event}: ${error.message}`));
    }
    this.events = [];
  }

  send(method: string, params: Record<string, unknown> = {}, sessionId?: string): Promise<CdpResult> {
    if (this.closed || this.toChrome.destroyed || this.toChrome.writableEnded)
      return Promise.reject(new Error(`CDP ${method}: connection closed`));
    const { promise, resolve, reject } = Promise.withResolvers<CdpResult>();
    const id = ++this.nextId;
    const timeout = setTimeout((): void => {
      this.commands.delete(id);
      reject(new Error(`CDP ${method} timed out`));
    }, 30_000);
    this.commands.set(id, { method, resolve, reject, timeout });
    this.toChrome.write(JSON.stringify({ id, method, params, sessionId }) + "\0");
    return promise;
  }

  once(event: string, sessionId: string): Promise<void> {
    if (this.closed) return Promise.reject(new Error(`CDP ${event}: connection closed`));
    const { promise, resolve, reject } = Promise.withResolvers<void>();
    const timeout = setTimeout((): void => {
      this.events = this.events.filter((pending: PendingEvent): boolean => pending !== entry);
      reject(new Error(`CDP ${event} timed out`));
    }, 30_000);
    const entry: PendingEvent = { event, sessionId, resolve, reject, timeout };
    this.events.push(entry);
    return promise;
  }
}

function displayPath(path: string): string {
  const local = relative(process.cwd(), path);
  return local.startsWith("..") ? path : local;
}

async function main(): Promise<number> {
  mkdirSync(OUT, { recursive: true });
  const names = process.argv.length > 2 ? process.argv.slice(2) :
    [...new Bun.Glob("*.html").scanSync({ cwd: SRC })].map((path: string): string => basename(path, ".html")).sort();
  const diagrams: Diagram[] = [];
  let failed = false;
  if (names.length === 0) {
    console.error(`no diagrams in ${displayPath(SRC)}`);
    return 1;
  }
  for (const name of names) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) {
      console.error(`invalid diagram name: ${name}`);
      failed = true;
      continue;
    }
    const path = join(SRC, `${name}.html`);
    if (!statSync(path, { throwIfNoEntry: false })?.isFile()) {
      console.error(`${displayPath(path)} not found`);
      failed = true;
      continue;
    }
    const html = await Bun.file(path).text();
    const size = /<meta name="render-size" content="(\d+)x(\d+)">/.exec(html);
    if (!size) {
      console.error(`${name}.html: missing <meta name="render-size" content="WxH">`);
      failed = true;
      continue;
    }
    const scale = /<meta name="render-scale" content="(\d+)">/.exec(html)?.[1] ?? "2";
    const width = Number(size[1]);
    const height = Number(size[2]);
    const scaleN = Number(scale);
    if (!width || !height || !scaleN) {
      console.error(`${name}.html: render-size and render-scale must be positive`);
      failed = true;
      continue;
    }
    diagrams.push({ name, width, height, scale: scaleN });
  }
  if (failed) return 1;

  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(req: Request): Response {
      try {
        const path = resolve(join(SRC, decodeURIComponent(new URL(req.url).pathname)));
        if (path.startsWith(SRC + sep) && statSync(path, { throwIfNoEntry: false })?.isFile())
          return new Response(Bun.file(path));
      } catch {
        // Malformed URLs and paths outside the source tree are not served.
      }
      return new Response("Not found", { status: 404 });
    },
  });
  let profile: string | null = null;
  let chromeProcess: ChildProcess | null = null;
  let chromeExited: Promise<void> | null = null;
  let cdp: Cdp | null = null;
  try {
    const chrome = process.env.CHROME ?? [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      Bun.which("google-chrome"), Bun.which("google-chrome-stable"),
      Bun.which("chromium"), Bun.which("chromium-browser"),
    ].find((path: string | null): boolean => path !== null && existsSync(path));
    if (!chrome) throw new Error("Chrome not found; set CHROME to a Chrome or Chromium binary");
    profile = mkdtempSync(join(tmpdir(), "av-render-"));
    const child = spawn(chrome, [
      "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
      "--no-default-browser-check", "--disable-extensions", "--font-render-hinting=none",
      "--force-color-profile=srgb", "--remote-debugging-pipe", "--user-data-dir=" + profile, "about:blank",
    ], { stdio: ["ignore", "ignore", "inherit", "pipe", "pipe"] });
    chromeProcess = child;
    chromeExited = new Promise<void>((resolve): void => {
      child.once("close", (): void => resolve());
    });
    child.once("error", (error: Error): void => cdp?.close(error));
    child.once("exit", (): void => cdp?.close(new Error("Chrome exited")));
    // Chrome reads CDP from fd 3 and writes NUL-delimited replies to fd 4; no TCP listener.
    const toChrome = child.stdio[3];
    const fromChrome = child.stdio[4];
    if (!(toChrome instanceof Writable) || !(fromChrome instanceof Readable))
      throw new Error("Chrome debugging pipes unavailable");
    cdp = new Cdp(toChrome, fromChrome);
    const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank" });
    if (!targetId) throw new Error("Chrome did not create a page target");
    const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
    if (!sessionId) throw new Error("Chrome did not attach to the page target");
    await cdp.send("Page.enable", {}, sessionId);
    for (const { name, width, height, scale } of diagrams) {
      try {
        await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: scale, mobile: false }, sessionId);
        await cdp.send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } }, sessionId);
        const loaded = cdp.once("Page.loadEventFired", sessionId);
        await Promise.all([
          loaded,
          cdp.send("Page.navigate", { url: `http://127.0.0.1:${server.port}/${name}.html` }, sessionId)
            .then((navigation: CdpResult): void => {
              if (navigation.errorText) throw new Error(navigation.errorText);
            }),
        ]);
        const checked = await cdp.send("Runtime.evaluate", { expression: CHECK, awaitPromise: true, returnByValue: true }, sessionId);
        if (checked.exceptionDetails) throw new Error(`page check threw: ${checked.exceptionDetails.text}`);
        const errors = checked.result?.value;
        if (!errors) throw new Error("page check returned no result");
        if (errors.length > 0) {
          for (const error of errors) console.error(`${name}: ${error}`);
          failed = true;
          continue;
        }
        const { data } = await cdp.send("Page.captureScreenshot", { format: "png" }, sessionId);
        if (!data) throw new Error("Chrome returned no screenshot");
        const output = join(OUT, `${name}.png`);
        await Bun.write(output, Buffer.from(data, "base64"));
        console.log(`${displayPath(output)} ${width * scale}x${height * scale}`);
      } catch (error) {
        console.error(`${name}: ${error instanceof Error ? error.message : String(error)}`);
        failed = true;
      }
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    failed = true;
  } finally {
    if (cdp) await cdp.send("Browser.close").catch((): void => {});
    if (chromeProcess) {
      if (chromeProcess.exitCode === null && chromeProcess.signalCode === null) chromeProcess.kill();
      await chromeExited;
    }
    server.stop(true);
    if (profile) rmSync(profile, { recursive: true, force: true });
  }
  return failed ? 1 : 0;
}

process.exitCode = await main();
