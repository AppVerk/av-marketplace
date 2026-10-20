// Draws the arrows of a README diagram once its fonts have loaded; see render.ts.
// drawWires([{ from, to, fromSide = "right", toSide = "left", via, kind }, ...])
// from/to/via are element ids; sides are "left" | "right" | "top" | "bottom";
// via runs a horizontal segment through that element's vertical centre and ends on the target's top side, or, for toSide "left",
// along the left margin into the target's left side (so wires never cross the band labels); kind "loop" draws a dashed amber arrow.
(function () {
  const STANDOFF = 24;
  const LOOP_DEPTH = 26;
  const NS = "http://www.w3.org/2000/svg";
  const MARKERS = [["arrow", "#7A8699"], ["arrow-loop", "#F2A93B"]];

  function anchor(el, side, origin) {
    const r = el.getBoundingClientRect();
    const cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
    const point = { left: [r.left, cy], right: [r.right, cy], top: [cx, r.top], bottom: [cx, r.bottom] }[side];
    if (!point) throw new Error("unknown side " + side);
    return [point[0] - origin.left, point[1] - origin.top];
  }

  function route(a, b, fromSide, toSide, viaY) {
    if (viaY !== undefined) {
      let start;
      if (fromSide === "bottom") start = [a, [a[0], viaY]];
      else if (fromSide === "right" || fromSide === "left") {
        const out = a[0] + (fromSide === "right" ? STANDOFF : -STANDOFF);
        start = [a, [out, a[1]], [out, viaY]];
      } else throw new Error("unsupported via wire from " + fromSide);
      if (toSide === "top") return [...start, [b[0], viaY], b];
      if (toSide === "left") { const lx = b[0] - STANDOFF; return [...start, [lx, viaY], [lx, b[1]], b]; }
      throw new Error("a via wire must end on a top or left side");
    }
    const pair = fromSide + ">" + toSide;
    if (pair === "right>left" || pair === "left>right") { const mx = (a[0] + b[0]) / 2; return [a, [mx, a[1]], [mx, b[1]], b]; }
    if (pair === "bottom>top") { const my = (a[1] + b[1]) / 2; return [a, [a[0], my], [b[0], my], b]; }
    if (pair === "bottom>bottom") { const ly = Math.max(a[1], b[1]) + LOOP_DEPTH; return [a, [a[0], ly], [b[0], ly], b]; }
    throw new Error("unsupported wire sides " + pair);
  }

  window.drawWires = function (specs) {
    document.fonts.ready.then(() => {
      const card = document.querySelector(".card");
      const svg = card && card.querySelector("svg.wires");
      if (!svg) {
        document.body.dataset.wireError = "drawWires needs a .card containing svg.wires";
        return;
      }
      const origin = card.getBoundingClientRect();
      svg.setAttribute("viewBox", `0 0 ${origin.width} ${origin.height}`);
      const defs = document.createElementNS(NS, "defs");
      for (const [id, color] of MARKERS) {
        const marker = document.createElementNS(NS, "marker");
        for (const [k, v] of Object.entries({ id, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto" })) marker.setAttribute(k, v);
        const head = document.createElementNS(NS, "path");
        head.setAttribute("d", "M0,0 L10,5 L0,10 z");
        head.setAttribute("fill", color);
        marker.appendChild(head);
        defs.appendChild(marker);
      }
      svg.appendChild(defs);
      let drawn = 0;
      for (const { from, to, fromSide = "right", toSide = "left", via, kind } of specs) {
        try {
          const ids = [from, to, via].filter(Boolean);
          const missing = ids.find((id) => !document.getElementById(id));
          if (missing) throw new Error("no element #" + missing);
          const viaY = via ? anchor(document.getElementById(via), "left", origin)[1] : undefined;
          const points = route(anchor(document.getElementById(from), fromSide, origin), anchor(document.getElementById(to), toSide, origin), fromSide, toSide, viaY)
            .filter((p, i, all) => i === 0 || p[0] !== all[i - 1][0] || p[1] !== all[i - 1][1]);
          const path = document.createElementNS(NS, "path");
          path.setAttribute("d", points.map((p, i) => (i ? "L" : "M") + p[0] + "," + p[1]).join(" "));
          path.setAttribute("class", kind === "loop" ? "wire loop" : "wire");
          path.setAttribute("marker-end", kind === "loop" ? "url(#arrow-loop)" : "url(#arrow)");
          svg.appendChild(path);
          drawn += 1;
        } catch (error) {
          document.body.dataset.wireError = `${from} -> ${to}: ${error.message}`;
          return;
        }
      }
      document.body.dataset.wires = String(drawn);
    });
  };
})();
