// `::: diagram` の中に書いた線の記法 (`in.right -> model.left` など) を読み、
// 図の要素に data-edges として持たせる。実際に線を描くのは、スライドに埋め込むスクリプト (connector.js)。

const fs = require("node:fs");
const path = require("node:path");

// connector.js の正本はデザインシステムの側にある。配るときは、同じディレクトリにコピーされる
const connectorPath = [
  path.join(__dirname, "connector.js"),
  path.join(__dirname, "../../design-system/src/connector.js"),
].find((candidate) => fs.existsSync(candidate));

const { parseEdge } = require(connectorPath);

const isDiagram = (token) =>
  token.type === "modern_container_open" &&
  (token.attrGet("class") || "").split(/\s+/).includes("diagram");

const ID_IN_HTML = /\bid\s*=\s*["']([^"']+)["']/g;

const diagram = (md, options = {}) => {
  // 既定では connector.js の中身をそのまま埋め込む
  const script = options.script ?? fs.readFileSync(connectorPath, "utf8");

  // marp の HTML の許可リストを通さずに出すため、専用の token にする
  md.renderer.rules.modern_diagram_script = () => `<script>${script}</script>\n`;

  // 段落が inline の処理に入る前に、線の記法を取り除く
  md.core.ruler.after("block", "modern_diagram", (state) => {
    if (state.inlineMode) return;

    const tokens = state.tokens;
    const remove = new Set();
    let lastDiagramWithEdges = null;

    for (let open = 0; open < tokens.length; open++) {
      if (!isDiagram(tokens[open])) continue;

      // この図の閉じを探す
      let depth = 0;
      let close = open;
      for (let i = open; i < tokens.length; i++) {
        if (tokens[i].type === "modern_container_open") depth += 1;
        if (tokens[i].type === "modern_container_close") depth -= 1;
        if (depth === 0) {
          close = i;
          break;
        }
      }

      const names = new Set();
      const candidates = [];

      for (let i = open + 1; i < close; i++) {
        const token = tokens[i];

        if (token.type === "modern_container_open" && token.attrGet("id")) {
          names.add(token.attrGet("id"));
        }
        if (token.type === "html_block" || token.type === "inline") {
          for (const match of token.content.matchAll(ID_IN_HTML)) names.add(match[1]);
        }

        // 全ての行が線の記法である段落だけを、記法として扱う
        if (
          token.type === "paragraph_open" &&
          tokens[i + 1]?.type === "inline" &&
          tokens[i + 2]?.type === "paragraph_close"
        ) {
          const lines = tokens[i + 1].content.split("\n");
          const parsed = lines.map(parseEdge);
          if (parsed.every(Boolean)) candidates.push({ index: i, edges: parsed });
        }
      }

      const edges = [];
      for (const candidate of candidates) {
        remove.add(candidate.index).add(candidate.index + 1).add(candidate.index + 2);
        for (const edge of candidate.edges) {
          const missing = [edge.from, edge.to].filter((name) => !names.has(name));
          if (missing.length > 0) {
            console.warn(
              `[modern] 図の線 "${edge.from} -> ${edge.to}" は描けません。この図に "${missing.join('", "')}" という名前の要素がありません。`,
            );
          } else {
            edges.push(edge);
          }
        }
      }

      if (edges.length > 0) {
        tokens[open].attrSet("data-edges", JSON.stringify(edges));
        lastDiagramWithEdges = close;
      }
    }

    if (remove.size === 0) return;

    const result = [];
    tokens.forEach((token, index) => {
      // スクリプトは文書に 1 回だけ、最後の図の閉じの直前に置く
      if (index === lastDiagramWithEdges) {
        const scriptToken = new state.Token("modern_diagram_script", "", 0);
        scriptToken.block = true;
        result.push(scriptToken);
      }
      if (!remove.has(index)) result.push(token);
    });
    state.tokens = result;
  });
};

module.exports = diagram;
