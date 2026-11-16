図の中の 1 つの要素を表す枠。色で役割を示す。

## 使う場面

- 処理の流れ、モデルの構成、データの関係を図にするとき。
- 中身は短い言葉 (1 行。補足を足して 2 行まで)。文を入れたいときは `Card` を使う。

## 種類

| 種類 | 役割 | 見た目 |
|---|---|---|
| (なし) | 入力、データ | 白地、濃い灰の枠 |
| `dark` | 処理、モデル | 濃い灰の地、白い文字 |
| `light` | 中間の結果 | 薄い青の地、青の枠 |
| `blue-fill` | 最終的な出力、結論 | 青の地、白い文字 |
| `warn` | 問題、否定 | 薄い赤の地、赤の枠 |
| `muted` | 未定、対象外 | 薄い灰の地、破線の枠 |

`square` を足すと、角丸がなくなる (`class="box dark square"`、React では `square`、marp では `::: box dark square`)。どの種類とも組み合わせられる。

## 渡すもの

- 中身の言葉。
- 補足 (任意)。`sub` の class を付けた要素か、React では `sub`。
- 名前 (任意)。線でつなぐときに `id` として使う。

## 書き方

```html
<div class="box dark" id="model">ResNet50<span class="sub">ImageNet 事前学習</span></div>
```

```jsx
<Modern.Box variant="dark" id="model" sub="ImageNet 事前学習">ResNet50</Modern.Box>
```

marp:

```markdown
::: box dark #model
ResNet50<span class="sub">ImageNet 事前学習</span>
:::
```

## 決まり

- 1 つの図で、同じ役割には同じ種類を使う。
- `blue-fill` は 1 つの図に 1 つまで。最も伝えたい結論に使う。
- 1 つの図の中では、角丸ありと `square` を混ぜない。
- 色だけで区別しない。役割は、中の言葉でも分かるようにする。
- 中身は折り返さない。長いときは言葉を削る。
