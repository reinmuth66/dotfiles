---
tags: [skill-creator]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

slides.md の最後に、提案手法の処理の流れを図にしたスライドを 1 枚足して。流れは、画像とメタデータ (フォロワー数など) を別々のエンコーダに入れて、2 つの特徴を結合し、分類器でいいね数の多さを予測する。予測の誤差は、2 つのエンコーダの両方に戻して学習する。戻る線は、進む線と見分けられるようにして。足したら PDF にして、図が崩れていないか確かめて。

Input files: slides.md
