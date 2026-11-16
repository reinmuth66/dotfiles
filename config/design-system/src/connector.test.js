const test = require("node:test");
const assert = require("node:assert/strict");
const { parseEdge, route, autoSides, labelPoint, plan, shareBends } = require("./connector.js");

const A = { x: 0, y: 0, width: 100, height: 40 };
const right = { x: 200, y: 0, width: 100, height: 40 };
const lowerRight = { x: 200, y: 100, width: 100, height: 40 };
const below = { x: 0, y: 100, width: 100, height: 40 };

test("route: 向かい合う辺が同じ高さなら直線", () => {
  assert.equal(route(A, right, "right", "left"), "M100 20H200");
});

test("route: 向かい合う辺がずれていれば、中間で 1 回折れる", () => {
  assert.equal(route(A, lowerRight, "right", "left"), "M100 20H150V120H200");
  assert.equal(route(A, lowerRight, "bottom", "top"), "M50 40V70H250V100");
});

test("route: 直交する辺は L 字", () => {
  assert.equal(route(A, lowerRight, "bottom", "left"), "M50 40V120H200");
  assert.equal(route(A, lowerRight, "right", "top"), "M100 20H250V100");
});

test("route: 同じ向きの辺はコの字で、外側を 24 離れて通る", () => {
  assert.equal(route(A, lowerRight, "top", "top"), "M50 0V-24H250V100");
  assert.equal(route(A, lowerRight, "bottom", "bottom"), "M50 40V164H250V140");
  assert.equal(route(A, lowerRight, "left", "left"), "M0 20H-24V120H200");
  assert.equal(route(A, lowerRight, "right", "right"), "M100 20H324V120H300");
});

test("route: 辺を省くと、位置関係から選ぶ", () => {
  assert.deepEqual(autoSides(A, right), ["right", "left"]);
  assert.deepEqual(autoSides(right, A), ["left", "right"]);
  assert.deepEqual(autoSides(A, below), ["bottom", "top"]);
  assert.deepEqual(autoSides(below, A), ["top", "bottom"]);
  assert.equal(route(A, right, null, null), "M100 20H200");
  assert.equal(route(A, below, null, null), "M50 40V100");
});

test("route: 片方の辺だけ省いても描ける", () => {
  assert.equal(route(A, lowerRight, "bottom", null), "M50 40V120H200");
  assert.equal(route(A, lowerRight, null, "top"), "M100 20H250V100");
  assert.equal(route(A, right, "right", null), "M100 20H200");
  assert.equal(route(A, below, null, "top"), "M50 40V100");
});

test("route: 片方の辺を省いたとき、相手が広い要素なら、中を通らずに向かい合う辺に入る", () => {
  const narrow = { x: 50, y: 0, width: 100, height: 40 };
  const wide = { x: 0, y: 100, width: 400, height: 40 };
  // 下から出た線が、広い要素の上の辺に入る (左の辺に内側から入らない)
  // 範囲が重なっているので、段を付けずにまっすぐ入る
  assert.equal(route(narrow, wide, "bottom", null), "M100 40V100");
  assert.equal(route(wide, narrow, null, "bottom"), "M100 100V40");

  const tall = { x: 200, y: -100, width: 60, height: 300 };
  assert.equal(route(A, tall, "right", null), "M100 20H200");
  assert.equal(route(tall, A, null, "right"), "M200 20H100");
});

test("labelPoint: 最も長い区間の中点に置く", () => {
  assert.deepEqual(labelPoint("M100 20H200"), { x: 150, y: 20 });
  // コの字: 横の区間が最も長い
  assert.deepEqual(labelPoint("M50 40V164H250V140"), { x: 150, y: 164 });
  // 同じ長さなら、先に出てくる区間
  assert.deepEqual(labelPoint("M0 0H10V10"), { x: 5, y: 0 });
});

test("parseEdge: 辺つきの矢印", () => {
  assert.deepEqual(parseEdge("in.right -> model.left"), {
    from: "in",
    fromSide: "right",
    to: "model",
    toSide: "left",
    kind: "arrow",
    label: null,
    options: [],
  });
});

test("parseEdge: 辺を省ける", () => {
  const edge = parseEdge("in -> model");
  assert.equal(edge.fromSide, null);
  assert.equal(edge.toSide, null);
});

test("parseEdge: 線の種類", () => {
  assert.equal(parseEdge("a -- b").kind, "line");
  assert.equal(parseEdge("a <-> b").kind, "both");
  assert.equal(parseEdge("a -> b").kind, "arrow");
});

test("parseEdge: ラベルと指定", () => {
  assert.equal(parseEdge("a -> b : 再学習").label, "再学習");
  assert.deepEqual(parseEdge("a -> b {blue dashed}").options, ["blue", "dashed"]);
  const both = parseEdge("a.top -> b.bottom {red} : 戻す: もう一度");
  assert.deepEqual(both.options, ["red"]);
  assert.equal(both.label, "戻す: もう一度");
});

test("parseEdge: 記法でない行は null", () => {
  assert.equal(parseEdge("これは -> ただの文"), null);
  assert.equal(parseEdge("a.middle -> b"), null);
  assert.equal(parseEdge("a -> b {green}"), null);
  assert.equal(parseEdge("a -> "), null);
  assert.equal(parseEdge("a → b"), null);
  assert.equal(parseEdge(""), null);
});

test("route: コの字の離れは、5 つ目の引数で変えられる", () => {
  assert.equal(route(A, lowerRight, "top", "top", 40), "M50 0V-40H250V100");
  assert.equal(route(A, lowerRight, "right", "right", 8), "M100 20H308V120H300");
});

// 高さの違う 2 つの要素。中心は 10 ずれているが、縦の範囲は重なっている
const short = { x: 0, y: 20, width: 100, height: 40 };
const tall = { x: 200, y: 0, width: 100, height: 100 };

test("route: 向かい合う辺の範囲が重なっていれば、段を付けずに直線で結ぶ", () => {
  // 重なりは y = 20〜60。その中央の 40 を通す
  assert.equal(route(short, tall, "right", "left"), "M100 40H200");
  assert.equal(route(tall, short, "left", "right"), "M200 40H100");
  // 縦の並びでも同じ
  const narrow = { x: 20, y: 0, width: 40, height: 40 };
  const wide = { x: 0, y: 100, width: 100, height: 40 };
  assert.equal(route(narrow, wide, "bottom", "top"), "M40 40V100");
});

test("route: 重なりが角丸より狭いときは、直線にせず中間で折れる", () => {
  const barely = { x: 200, y: 30, width: 100, height: 40 };
  // A は y = 0〜40、barely は y = 30〜70。重なりは 10 しかない
  assert.equal(route(A, barely, "right", "left"), "M100 20H150V50H200");
});

test("route: 折れる位置は、6 つ目の引数で変えられる", () => {
  assert.equal(route(A, lowerRight, "right", "left", 24, 120), "M100 20H120V120H200");
});

test("shareBends: 同じ辺から出る線は、出る側に最も近い位置で揃えて折る", () => {
  const near = { x: 200, y: -100, width: 100, height: 40 };
  const far = { x: 260, y: 100, width: 100, height: 40 };
  const plans = [
    { edge: { from: "a", to: "near" }, ...plan(A, near, "right", "left") },
    { edge: { from: "a", to: "far" }, ...plan(A, far, "right", "left") },
  ];
  assert.deepEqual(plans.map((p) => p.bend), [150, 180]);
  shareBends(plans);
  assert.deepEqual(plans.map((p) => p.bend), [150, 150]);
});

test("shareBends: 同じ辺に入る線は、入る側に最も近い位置で揃えて折る", () => {
  const target = { x: 300, y: 0, width: 100, height: 40 };
  const nearSource = { x: 100, y: -100, width: 100, height: 40 };
  const farSource = { x: 0, y: 100, width: 100, height: 40 };
  const plans = [
    { edge: { from: "n", to: "t" }, ...plan(nearSource, target, "right", "left") },
    { edge: { from: "f", to: "t" }, ...plan(farSource, target, "right", "left") },
  ];
  assert.deepEqual(plans.map((p) => p.bend), [250, 200]);
  shareBends(plans);
  assert.deepEqual(plans.map((p) => p.bend), [250, 250]);
});

test("shareBends: 直線や L 字の線は、そのままにする", () => {
  const plans = [
    { edge: { from: "a", to: "r" }, ...plan(A, right, "right", "left") },
    { edge: { from: "a", to: "l" }, ...plan(A, lowerRight, "right", "left") },
  ];
  shareBends(plans);
  assert.equal(plans[0].bend, null);
  assert.equal(plans[1].bend, 150);
});
