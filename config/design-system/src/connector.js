// 図の中の要素同士を、直角に折れる線でつなぐ。
// marp のエンジンの拡張 (スライドに埋め込む) と、React の部品 (bundle.js) の両方が、このファイルを使う。
//   parseEdge  記法の 1 行を読む
//   route      2 つの矩形と辺から、線の経路を決める (DOM に触らない)
//   draw       ブラウザで、要素の位置を測って SVG を描く
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.ModernConnector = api;
    api.auto();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const SIDES = ["top", "right", "bottom", "left"];
  const OPTIONS = ["blue", "red", "dashed"];
  const KINDS = { "->": "arrow", "--": "line", "<->": "both" };
  // コの字の線が、要素の外側を通るときの離れ (space-6)
  const DETOUR = 24;

  const NAME = "([A-Za-z][\\w-]*)";
  const SIDE = "(?:\\.([a-z]+))?";
  const EDGE = new RegExp(
    `^${NAME}${SIDE}\\s*(<->|->|--)\\s*${NAME}${SIDE}\\s*(?:\\{([^}]*)\\})?\\s*(?::\\s*(.+?))?\\s*$`,
  );

  // 例: "in.right -> model.left {blue dashed} : ラベル"
  const parseEdge = (line) => {
    const match = EDGE.exec(String(line).trim());
    if (!match) return null;

    const [, from, fromSide, arrow, to, toSide, rawOptions, label] = match;
    if (fromSide && !SIDES.includes(fromSide)) return null;
    if (toSide && !SIDES.includes(toSide)) return null;

    const options = rawOptions ? rawOptions.trim().split(/\s+/).filter(Boolean) : [];
    if (options.some((option) => !OPTIONS.includes(option))) return null;

    return {
      from,
      fromSide: fromSide || null,
      to,
      toSide: toSide || null,
      kind: KINDS[arrow],
      label: label || null,
      options,
    };
  };

  const isVertical = (side) => side === "top" || side === "bottom";

  // 辺の中点
  const anchor = (rect, side) => {
    const centerX = rect.x + rect.width / 2;
    const centerY = rect.y + rect.height / 2;
    if (side === "top") return [centerX, rect.y];
    if (side === "bottom") return [centerX, rect.y + rect.height];
    if (side === "left") return [rect.x, centerY];
    return [rect.x + rect.width, centerY];
  };

  // 辺を省いたとき。離れている向き (横か縦) の、向かい合う辺を選ぶ
  const autoSides = (from, to) => {
    const gapX = Math.max(to.x - (from.x + from.width), from.x - (to.x + to.width));
    const gapY = Math.max(to.y - (from.y + from.height), from.y - (to.y + to.height));
    if (gapX >= gapY) {
      return to.x + to.width / 2 >= from.x + from.width / 2 ? ["right", "left"] : ["left", "right"];
    }
    return to.y + to.height / 2 >= from.y + from.height / 2 ? ["bottom", "top"] : ["top", "bottom"];
  };

  // 片方だけ省いたときは、指定された辺に向かい合う辺を使う
  const OPPOSITE = { top: "bottom", bottom: "top", left: "right", right: "left" };

  const number = (value) => String(Math.round(value * 100) / 100);

  // 点が、start から size の幅の中にあるか
  const within = (point, start, size) => point >= start - 0.5 && point <= start + size + 0.5;

  // SVG の path の d を返す
  const route = (from, to, fromSide, toSide) => {
    let sideA = fromSide;
    let sideB = toSide;
    if (!sideA && !sideB) {
      [sideA, sideB] = autoSides(from, to);
    } else if (!sideA) {
      // 入る点が自分の幅 (高さ) の中にあれば、向かい合う辺から出る。L 字にすると、線が自分の中を通ってしまう。
      // 外にあれば、入る辺と直交する辺から出て L 字にする
      const [x2, y2] = anchor(to, sideB);
      if (isVertical(sideB)) {
        if (within(x2, from.x, from.width)) sideA = OPPOSITE[sideB];
        else sideA = from.x + from.width / 2 < x2 ? "right" : "left";
      } else if (within(y2, from.y, from.height)) {
        sideA = OPPOSITE[sideB];
      } else {
        sideA = from.y + from.height / 2 < y2 ? "bottom" : "top";
      }
    } else if (!sideB) {
      // 出る点が相手の幅 (高さ) の中にあれば、向かい合う辺に入る。外にあれば L 字
      const [x1, y1] = anchor(from, sideA);
      if (isVertical(sideA)) {
        if (within(x1, to.x, to.width)) sideB = OPPOSITE[sideA];
        else sideB = to.x + to.width / 2 > x1 ? "left" : "right";
      } else if (within(y1, to.y, to.height)) {
        sideB = OPPOSITE[sideA];
      } else {
        sideB = to.y + to.height / 2 > y1 ? "top" : "bottom";
      }
    }

    const [x1, y1] = anchor(from, sideA);
    const [x2, y2] = anchor(to, sideB);
    const start = `M${number(x1)} ${number(y1)}`;
    const H = (x) => `H${number(x)}`;
    const V = (y) => `V${number(y)}`;

    // 同じ向きの辺: コの字で外側を回る
    if (sideA === sideB) {
      if (sideA === "top") return start + V(Math.min(y1, y2) - DETOUR) + H(x2) + V(y2);
      if (sideA === "bottom") return start + V(Math.max(y1, y2) + DETOUR) + H(x2) + V(y2);
      if (sideA === "left") return start + H(Math.min(x1, x2) - DETOUR) + V(y2) + H(x2);
      return start + H(Math.max(x1, x2) + DETOUR) + V(y2) + H(x2);
    }

    // 直交する辺: L 字
    if (isVertical(sideA) !== isVertical(sideB)) {
      return isVertical(sideA) ? start + V(y2) + H(x2) : start + H(x2) + V(y2);
    }

    // 向かい合う辺: 揃っていれば直線、ずれていれば中間で折れる
    if (isVertical(sideA)) {
      if (Math.abs(x1 - x2) < 0.5) return start + V(y2);
      return start + V((y1 + y2) / 2) + H(x2) + V(y2);
    }
    if (Math.abs(y1 - y2) < 0.5) return start + H(x2);
    return start + H((x1 + x2) / 2) + V(y2) + H(x2);
  };

  // ラベルを置く点。route が作った経路 (M、H、V だけ) の、最も長い区間の中点
  const labelPoint = (d) => {
    let x = 0;
    let y = 0;
    let best = null;
    for (const [, command, a, b] of d.matchAll(/([MHV])(-?[\d.]+)(?: (-?[\d.]+))?/g)) {
      const fromX = x;
      const fromY = y;
      if (command === "M") {
        x = Number(a);
        y = Number(b);
        continue;
      }
      if (command === "H") x = Number(a);
      else y = Number(a);
      const length = Math.abs(x - fromX) + Math.abs(y - fromY);
      if (!best || length > best.length) {
        best = { length, x: (fromX + x) / 2, y: (fromY + y) / 2 };
      }
    }
    return best ? { x: best.x, y: best.y } : { x, y };
  };

  const SVG_NS = "http://www.w3.org/2000/svg";
  let serial = 0;

  // 1 つの図に線を描く。描き直せるよう、前に描いた SVG は消す
  const drawDiagram = (diagram) => {
    for (const old of diagram.querySelectorAll(":scope > svg.diagram-edges")) old.remove();

    let edges;
    try {
      edges = JSON.parse(diagram.getAttribute("data-edges") || "[]");
    } catch {
      return;
    }
    if (!edges.length || !diagram.offsetWidth) return;

    const base = diagram.getBoundingClientRect();
    // marp はスライドを拡大・縮小して表示するので、画面上の大きさを元の大きさに戻す
    const scale = base.width / diagram.offsetWidth || 1;
    const rectOf = (element) => {
      const rect = element.getBoundingClientRect();
      return {
        x: (rect.left - base.left) / scale,
        y: (rect.top - base.top) / scale,
        width: rect.width / scale,
        height: rect.height / scale,
      };
    };

    const doc = diagram.ownerDocument;
    const svg = doc.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "diagram-edges");
    svg.setAttribute("aria-hidden", "true");

    const markerId = `modern-arrow-${(serial += 1)}`;
    const defs = doc.createElementNS(SVG_NS, "defs");
    const marker = doc.createElementNS(SVG_NS, "marker");
    marker.setAttribute("id", markerId);
    marker.setAttribute("viewBox", "0 0 10 10");
    marker.setAttribute("refX", "9");
    marker.setAttribute("refY", "5");
    marker.setAttribute("markerWidth", "7");
    marker.setAttribute("markerHeight", "7");
    marker.setAttribute("orient", "auto-start-reverse");
    const head = doc.createElementNS(SVG_NS, "path");
    head.setAttribute("d", "M0 0L10 5L0 10z");
    // 矢じりは線と同じ色にする
    head.setAttribute("fill", "context-stroke");
    marker.appendChild(head);
    defs.appendChild(marker);
    svg.appendChild(defs);
    diagram.appendChild(svg);

    for (const edge of edges) {
      // 名前は、この図の中だけで探す
      const from = diagram.querySelector(`#${CSS.escape(edge.from)}`);
      const to = diagram.querySelector(`#${CSS.escape(edge.to)}`);
      if (!from || !to) continue;

      const d = route(rectOf(from), rectOf(to), edge.fromSide, edge.toSide);
      const path = doc.createElementNS(SVG_NS, "path");
      path.setAttribute("d", d);
      path.setAttribute("class", ["diagram-edge", ...(edge.options || [])].join(" "));
      if (edge.kind !== "line") path.setAttribute("marker-end", `url(#${markerId})`);
      if (edge.kind === "both") path.setAttribute("marker-start", `url(#${markerId})`);
      svg.appendChild(path);

      if (edge.label) {
        const middle = labelPoint(d);
        const text = doc.createElementNS(SVG_NS, "text");
        text.setAttribute("class", ["diagram-label", ...(edge.options || [])].join(" "));
        text.setAttribute("x", number(middle.x));
        text.setAttribute("y", number(middle.y));
        text.textContent = edge.label;
        svg.appendChild(text);
      }
    }
  };

  const observed = new WeakSet();

  // root の中の全ての図に線を描く。図の大きさが変わったら描き直す
  const draw = (root) => {
    const scope = root || document;
    const diagrams = scope.querySelectorAll ? [...scope.querySelectorAll("[data-edges]")] : [];
    if (scope.matches && scope.matches("[data-edges]")) diagrams.unshift(scope);

    for (const diagram of diagrams) {
      drawDiagram(diagram);
      if (typeof ResizeObserver === "function" && !observed.has(diagram)) {
        observed.add(diagram);
        new ResizeObserver(() => drawDiagram(diagram)).observe(diagram);
      }
    }
  };

  // スライドに埋め込まれたとき。文字の幅が決まってから描く
  const auto = () => {
    if (typeof document === "undefined") return;
    const run = () => draw(document);
    const fonts = document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();
    fonts.then(run);
    if (typeof window !== "undefined") {
      window.addEventListener("load", run);
      window.addEventListener("resize", run);
    }
  };

  return { parseEdge, route, autoSides, labelPoint, draw, auto };
});
