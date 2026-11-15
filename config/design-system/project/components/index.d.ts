import type * as React from 'react';

/** 目次。番号は自動で振られる。 */
export interface TocProps extends React.OlHTMLAttributes<HTMLOListElement> {
  /** 章の名前の並び。番号は書かない。 */
  items: React.ReactNode[];
}
export declare function Toc(props: TocProps): React.ReactElement;

/** 説明をまとめる枠。 */
export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  /** accent は強調 (青の枠)、warn は問題 (赤の枠)。省くと細い灰の枠。 */
  variant?: 'accent' | 'warn';
  children?: React.ReactNode;
}
export declare function Card(props: CardProps): React.ReactElement;

/** 図の中の 1 つの要素。色で役割を示す。 */
export interface BoxProps extends React.HTMLAttributes<HTMLDivElement> {
  /** dark は処理、light は中間の結果、blue-fill は結論、warn は問題、muted は対象外。省くと入力。 */
  variant?: 'dark' | 'light' | 'blue-fill' | 'muted' | 'warn';
  /** 補足の 1 行。小さく、控えめな色で下に出る。 */
  sub?: React.ReactNode;
  /** Diagram の線でつなぐときの名前。 */
  id?: string;
  children?: React.ReactNode;
}
export declare function Box(props: BoxProps): React.ReactElement;

/** 横に並べる。 */
export interface RowProps extends React.HTMLAttributes<HTMLDivElement> {
  /** 中央に寄せる。 */
  center?: boolean;
  children?: React.ReactNode;
}
export declare function Row(props: RowProps): React.ReactElement;

/** 縦に並べる。 */
export interface ColProps extends React.HTMLAttributes<HTMLDivElement> {
  children?: React.ReactNode;
}
export declare function Col(props: ColProps): React.ReactElement;

/** 等幅の列に並べる。 */
export interface GridProps extends React.HTMLAttributes<HTMLDivElement> {
  /** 列の数。既定は 2。 */
  columns?: 2 | 3;
  children?: React.ReactNode;
}
export declare function Grid(props: GridProps): React.ReactElement;

/** 要素同士を線でつなぐ図。 */
export interface DiagramProps extends React.HTMLAttributes<HTMLDivElement> {
  /**
   * 線の一覧。1 本を 1 つの文字列で書く。
   * 例: "in.right -> model.left"、"a -- b"、"a <-> b"、"a -> b {blue dashed} : ラベル"
   * 辺は top、right、bottom、left。省くと、位置関係から選ぶ。
   */
  edges: string[];
  /** 配置の class を足すとき (例: "row center"、"grid3")。 */
  className?: string;
  /** 図の要素。線でつなぐものには id を付ける。 */
  children?: React.ReactNode;
}
export declare function Diagram(props: DiagramProps): React.ReactElement;

/** data-edges を付けた要素 (または、それを含む要素) を渡すと、線を描く。HTML を直接書いたとき用。 */
export declare function draw(root?: Element | Document): void;

declare global {
  interface Window {
    Modern: {
      Toc: typeof Toc;
      Card: typeof Card;
      Box: typeof Box;
      Row: typeof Row;
      Col: typeof Col;
      Grid: typeof Grid;
      Diagram: typeof Diagram;
      draw: typeof draw;
    };
  }
}
