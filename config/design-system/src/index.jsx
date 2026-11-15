// デザインシステム「modern」の React の部品。
// 見た目は components/bundle.css の class が決める。部品は、その class を付けた HTML を出すだけにする。
// esbuild が 1 つのスクリプトにまとめ、window.Modern に入れる (pkgs/design-system)。
import connector from "./connector.js";

// React は、このスクリプトより先に読み込まれた window.React を使う
const React = globalThis.React;

const cx = (...names) => names.filter(Boolean).join(" ");

// 目次。番号は CSS が振る
export const Toc = ({ items = [], className, ...rest }) => (
  <ol className={cx("toc", className)} {...rest}>
    {items.map((item, index) => (
      <li key={index}>{item}</li>
    ))}
  </ol>
);

// 説明をまとめる枠。variant は accent か warn
export const Card = ({ variant, className, children, ...rest }) => (
  <div className={cx("card", variant, className)} {...rest}>
    {children}
  </div>
);

// 図の中の要素。variant は dark、light、blue-fill、muted、warn。sub は補足の 1 行
export const Box = ({ variant, sub, className, children, ...rest }) => (
  <div className={cx("box", variant, className)} {...rest}>
    {children}
    {sub ? <span className="sub">{sub}</span> : null}
  </div>
);

export const Row = ({ center, className, children, ...rest }) => (
  <div className={cx("row", center && "center", className)} {...rest}>
    {children}
  </div>
);

export const Col = ({ className, children, ...rest }) => (
  <div className={cx("col", className)} {...rest}>
    {children}
  </div>
);

// 等幅の列。columns は 2 か 3
export const Grid = ({ columns = 2, className, children, ...rest }) => (
  <div className={cx(columns === 3 ? "grid3" : "grid2", className)} {...rest}>
    {children}
  </div>
);

// 要素同士を線でつなぐ図。edges は marp と同じ記法の文字列の並び
export const Diagram = ({ edges = [], className, children, ...rest }) => {
  const ref = React.useRef(null);
  const parsed = edges.map(connector.parseEdge).filter(Boolean);
  const data = JSON.stringify(parsed);

  // 中身が描かれてから、位置を測って線を引く
  React.useEffect(() => {
    if (ref.current) connector.draw(ref.current);
  }, [data]);

  return (
    <div ref={ref} className={cx("diagram", className)} data-edges={data} {...rest}>
      {children}
    </div>
  );
};

// HTML を直接書いたとき用。data-edges を付けた要素を渡すと、線を描く
export const draw = connector.draw;
