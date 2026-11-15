要素同士を線でつなぐ図。どの辺から出て、どの辺に入るかを指定でき、経路はそこから決まる。

## 使う場面

- 処理の流れ、データの流れ、要素の間の関係を見せるとき。
- 一直線の流れだけでなく、枝分かれ、合流、戻る線があるとき。

## 渡すもの

- 図の要素。それぞれに名前 (`id`) を付ける。たいていは `Box`。
- 要素の配置。`Row`、`Col`、`Grid` で並べる。線は配置に追従するので、位置を数値で書かない。
- 線の一覧。1 本を 1 行の記法で書く。

## 線の記法

```
出る要素.辺 -> 入る要素.辺 {指定} : ラベル
```

| 書き方 | 意味 |
|---|---|
| `in -> model` | 辺を省く。離れている向きの、向かい合う辺を選ぶ |
| `in.right -> model.left` | 右から出て、左に入る |
| `a -- b` | 矢じりのない線 |
| `a <-> b` | 両方向の矢印 |
| `a -> b : 再学習` | 線の上にラベル |
| `a -> b {blue}` | 青い線。ほかに `red`、`dashed`。並べて書ける (`{blue dashed}`) |

辺は `top`、`right`、`bottom`、`left`。

## 経路

経路は、出る辺と入る辺の組み合わせで決まる。線は直角にだけ折れる。

| 辺の組み合わせ | 経路 |
|---|---|
| 向かい合う辺 (`right` → `left`) で、位置が揃っている | 直線 |
| 向かい合う辺で、位置がずれている | 中間で 1 回、段を付ける |
| 直交する辺 (`bottom` → `left`) | L 字 |
| 同じ向きの辺 (`bottom` → `bottom`) | コの字。要素の外側を回る。戻る線に使う |

## 書き方

HTML では、`diagram` の class と、線の一覧を JSON にした `data-edges` を付ける。線を描くには、`ModernConnector.draw(要素)` を呼ぶ。React と marp では、これは自動で行われる。

```jsx
<Modern.Diagram edges={["in -> model", "model.bottom -> in.bottom {dashed} : 再学習"]}>
  <Modern.Row center>
    <Modern.Box id="in">入力</Modern.Box>
    <Modern.Box id="model" variant="dark">モデル</Modern.Box>
  </Modern.Row>
</Modern.Diagram>
```

marp:

```markdown
::: diagram row center
::: box #in
入力
:::
::: box dark #model
モデル
:::

in -> model
model.bottom -> in.bottom {dashed} : 再学習
:::
```

`::: diagram` に配置の名前を続けて書くと (`diagram row center`、`diagram grid3`)、図そのものがその配置になる。

## 決まり

- 線の色は役割で選ぶ。ふつうの流れは指定なし (灰)、強調したい流れは `blue`、問題や失敗の流れは `red`。
- `dashed` は、任意の流れ、戻る流れ、対象外の流れに使う。
- 1 つの図の線は 8 本くらいまで。それより多いときは、図を分ける。
- 線が要素やほかの線と重なるときは、出る辺と入る辺を変える。線は要素を自動でよけない。
- ラベルは短く (6 文字くらいまで)。線の最も長い区間の中央に置かれる。
- 斜めの線と曲線はない。

## 制限

- 線は、ブラウザが要素の位置を測ってから描く。marp では、PDF、PNG、PPTX、HTML への変換で描かれる。VS Code の marp のプレビューでは描かれない。
- 名前は、同じ図の中で一意にする。別の図の要素にはつなげない。
