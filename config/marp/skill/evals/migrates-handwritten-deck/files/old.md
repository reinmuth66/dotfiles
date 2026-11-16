---
marp: true
theme: default
paginate: true
footer: "1. はじめに"
style: |
  section { font-family: sans-serif; background: #f7f7f7; }
  .toc { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; font-size: 34px; }
  .toc-num { color: #005599; font-weight: bold; margin-right: 10px; }
  .mycard { border: 2px solid #ccc; border-radius: 8px; padding: 20px; background: white; box-shadow: 0 2px 8px rgba(0,0,0,0.2); }
  .mycard.hl { border-color: #005599; }
  .mycard.bad { border-color: #990008; }
  .cols { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px; }
  .flow { display: flex; align-items: center; justify-content: center; gap: 12px; }
  .node { border: 2px solid #222; border-radius: 8px; padding: 10px 16px; background: white; }
  .node.proc { background: #222; color: white; }
  .node.res { background: #005599; color: white; border-color: #005599; }
---

# キャッシュでAPIの応答を速くする
### 大西

---

# 目次

<div class="toc">
<div><span class="toc-num">1.</span>はじめに</div>
<div><span class="toc-num">2.</span>方法</div>
</div>

---

<!-- footer: "1. はじめに" -->

# <span class="toc-num">1.</span>はじめに

---

<!-- footer: "1. はじめに" -->

# 応答が遅い原因は、毎回の問い合わせ

<div class="cols">
<div class="mycard">
<h4>今のやり方</h4>
<ul><li>要求のたびにDBを読む</li></ul>
</div>
<div class="mycard bad">
<h4>問題</h4>
<ul><li>同じ内容を何度も読む</li><li style="font-size: 20px; color: #990008;">混雑時に応答が 2 秒を超える</li></ul>
</div>
<div class="mycard hl">
<h4>提案</h4>
<ul><li>結果を一定時間だけ覚えておく</li></ul>
</div>
</div>

---

<!-- footer: "2. 方法" -->

# <span class="toc-num">2.</span>方法

---

<!-- footer: "2. 方法" -->

# キャッシュにあれば、DBを読まない

<div class="flow">
<div class="node">要求</div>
<span style="font-size: 40px;">→</span>
<div class="node proc">キャッシュを確認</div>
<span style="font-size: 40px;">→</span>
<div class="node res" style="margin-top: -80px;">あれば返す</div>
<div class="node" style="margin-top: 80px; margin-left: -150px;">なければDBを読む</div>
</div>
