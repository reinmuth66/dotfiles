const test = require("node:test");
const assert = require("node:assert/strict");
const { parseEdge, route, autoSides, labelPoint } = require("./connector.js");

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
