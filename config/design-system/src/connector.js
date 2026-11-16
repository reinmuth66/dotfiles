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
  // コの字の線が、要素の外側を通るときの離れ。ブラウザでは --space-6 の値を使い、これは読めないときの値
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

  // 向かい合う辺を直線で結ぶとき、線が角丸にかからないよう、端から空ける幅 (radius-md)
  const INSET = 8;

  // 2 つの範囲が重なっていれば、重なりの中央を返す。直線を通せるだけの幅がなければ null
  const overlapCenter = (startA, sizeA, startB, sizeB) => {
    const low = Math.max(startA, startB);
    const high = Math.min(startA + sizeA, startB + sizeB);
    return high - low >= INSET * 2 ? (low + high) / 2 : null;
  };

  // 省かれた辺を決める
  const resolveSides = (from, to, fromSide, toSide) => {
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
    return [sideA, sideB];
  };

  // 経路の下調べ。辺と、「向かい合う辺を、中間で 1 回折れて結ぶ」ときの折れる位置 (bend) を返す。
  // 直線、L 字、コの字のときは、bend は null。origin と target は、線の進む向きでの始点と終点の位置
  const plan = (from, to, fromSide, toSide) => {
    const [sideA, sideB] = resolveSides(from, to, fromSide, toSide);
    const [x1, y1] = anchor(from, sideA);
    const [x2, y2] = anchor(to, sideB);
    const result = { sideA, sideB, bend: null, origin: null, target: null };

    if (sideA === sideB || isVertical(sideA) !== isVertical(sideB)) return result;
    if (isVertical(sideA)) {
      if (overlapCenter(from.x, from.width, to.x, to.width) !== null) return result;
      return { ...result, bend: (y1 + y2) / 2, origin: y1, target: y2 };
    }
    if (overlapCenter(from.y, from.height, to.y, to.height) !== null) return result;
    return { ...result, bend: (x1 + x2) / 2, origin: x1, target: x2 };
  };

  // 1 つの辺から何本も出る線、1 つの辺に何本も入る線の、折れる位置を揃える。
  // 揃えないと、相手の位置によって折れる位置が少しずつずれ、枝分かれが段々に見える
  const shareBends = (plans) => {
    const done = new Set();
    const align = (keyOf, anchorOf) => {
      const groups = new Map();
      for (const item of plans) {
        if (item.bend === null || done.has(item)) continue;
        const key = keyOf(item);
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(item);
      }
      for (const group of groups.values()) {
        if (group.length < 2) continue;
        // 束ねる側 (出る辺、または入る辺) に最も近い位置を選ぶ。どの線にとっても、始点と終点の間に収まる
        const distance = (item) => Math.abs(item.bend - anchorOf(item));
        const shared = group.reduce((best, item) => (distance(item) < distance(best) ? item : best)).bend;
        for (const item of group) {
          item.bend = shared;
          done.add(item);
        }
      }
    };
    align(
      (item) => `${item.edge.from}.${item.sideA}`,
      (item) => item.origin,
    );
    align(
      (item) => `${item.edge.to}.${item.sideB}`,
      (item) => item.target,
    );
    return plans;
  };

  // SVG の path の d を返す。bend は、中間で折れる経路の折れる位置 (省くと中間)
  const route = (from, to, fromSide, toSide, detour = DETOUR, bend = null) => {
    const [sideA, sideB] = resolveSides(from, to, fromSide, toSide);
    const [x1, y1] = anchor(from, sideA);
    const [x2, y2] = anchor(to, sideB);
    const start = `M${number(x1)} ${number(y1)}`;
    const H = (x) => `H${number(x)}`;
    const V = (y) => `V${number(y)}`;

    // 同じ向きの辺: コの字で外側を回る
    if (sideA === sideB) {
      if (sideA === "top") return start + V(Math.min(y1, y2) - detour) + H(x2) + V(y2);
      if (sideA === "bottom") return start + V(Math.max(y1, y2) + detour) + H(x2) + V(y2);
      if (sideA === "left") return start + H(Math.min(x1, x2) - detour) + V(y2) + H(x2);
      return start + H(Math.max(x1, x2) + detour) + V(y2) + H(x2);
    }

    // 直交する辺: L 字
    if (isVertical(sideA) !== isVertical(sideB)) {
      return isVertical(sideA) ? start + V(y2) + H(x2) : start + H(x2) + V(y2);
    }

    // 向かい合う辺: 2 つの要素の範囲が重なっていれば、重なりの中央を通る直線。
    // 辺の中点同士を結ぶと、高さの違う要素の間で、線が数 px だけ折れてしまう
    if (isVertical(sideA)) {
      const x = overlapCenter(from.x, from.width, to.x, to.width);
      if (x !== null) return `M${number(x)} ${number(y1)}` + V(y2);
      return start + V(bend ?? (y1 + y2) / 2) + H(x2) + V(y2);
    }
    const y = overlapCenter(from.y, from.height, to.y, to.height);
    if (y !== null) return `M${number(x1)} ${number(y)}` + H(x2);
    return start + H(bend ?? (x1 + x2) / 2) + V(y2) + H(x2);
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

  // 1 つの図に線を描く。図の直下の svg.diagram-edges があれば、その中身だけを描き直す。
  // React の部品は、この svg を自分で出す (React が管理する要素に、外から要素を足さないため)
  const drawDiagram = (diagram) => {
    let svg = diagram.querySelector(":scope > svg.diagram-edges");
    if (svg) svg.replaceChildren();

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
    if (!svg) {
      svg = doc.createElementNS(SVG_NS, "svg");
      svg.setAttribute("class", "diagram-edges");
      svg.setAttribute("aria-hidden", "true");
      diagram.appendChild(svg);
    }

    // コの字の離れは、トークン (space-6) から取る
    const view = doc.defaultView;
    const detour =
      (view && parseFloat(view.getComputedStyle(diagram).getPropertyValue("--space-6"))) || DETOUR;

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

    // 先に全ての線の辺と折れる位置を決め、枝分かれの折れる位置を揃えてから描く
    const plans = [];
    for (const edge of edges) {
      // 名前は、この図の中だけで探す
      const from = diagram.querySelector(`#${CSS.escape(edge.from)}`);
      const to = diagram.querySelector(`#${CSS.escape(edge.to)}`);
      if (!from || !to) continue;
      const fromRect = rectOf(from);
      const toRect = rectOf(to);
      plans.push({ edge, fromRect, toRect, ...plan(fromRect, toRect, edge.fromSide, edge.toSide) });
    }
    shareBends(plans);

    for (const { edge, fromRect, toRect, sideA, sideB, bend } of plans) {
      const d = route(fromRect, toRect, sideA, sideB, detour, bend);
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

  return { parseEdge, route, autoSides, labelPoint, plan, shareBends, draw, auto };
});
