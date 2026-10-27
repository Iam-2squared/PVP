# スタート画面・ホーム UI

Godot 4.6.3向けの独立したUIです。F5でスタート画面を表示し、**START**でホームへ進みます。

- ホーム：名前、レベル、職業、名声、所持金、現在EXP、次レベルまでのEXP。
- ステータス：README準拠の8能力を4列×2行で表示。下の八角形グラフは、表示中の最大能力値を基準にした相対表示です。ゲーム上の上限ではありません。
- 中央：職業と男女設定に合う完成キャラクターを表示。待機アニメーション付き。武器が未装備なら手持ち武器も非表示。
- 装備：メイン武器、頭・胴・脚・足。未装備時と保有武器なしの状態にも対応。
- スキル：現在職業のスキル名とスキルレベル。
- スキルツリー：第一6職の完成キャラクターを表示。右上の男性・女性で全12体をプレビュー可能。カードをタップすると、対応武器、補正、スキル、第二職業への分岐を表示。職業の閲覧だけを行い、転職は実行しません。
- 詳細はスクロール可能。閉じる、領域外のタップ、Escで戻れます。ホーム・ツリー・タイトルの移動に対応します。

初期状態の「冒険者・戦士・Lv1・0EXP・所持金0・能力値0・強撃Lv1・未装備」は**表示確認用のサンプル**です。確定した初期値や保存データではありません。通貨名、スキルEXP曲線などの未決定ルールは追加していません。オンライン・保存・装備変更・戦闘との連携は本変更の対象外です。

## 画面例

[スタート画面](frontend-title.png) · [ホーム](frontend-home.png) · [スキルツリー（男性）](frontend-tree.png) · [スキルツリー（女性）](frontend-tree-female.png)

![ホーム](frontend-home.png)

## 並行開発との境界

新規画面は `scenes/frontend/`、スクリプトは `scripts/frontend/`、表示用素材は `assets/frontend/` に分離しています。キャラクター制作ブランチ `feat/character-playground` を取り込んだ上で、完成モデルを親プロジェクトから表示できる形に接続しました。起動シーン指定は `project.godot` の1行のみ変更し、既存の王都・移動・HUD・練習画面のコードは変更していません。

既存の `scenes/main.tscn`、王都生成物、HUD、プレイヤー制御、既存フォントは変更していません。王都の確認は、Godotで `scenes/main.tscn` を開き **F6**、または次のように起動してください。

```sh
godot --path . res://scenes/main.tscn
```

既存の `tools/capture_preview.gd` と `tools/browser_smoke.py` は王都用です。画面の撮影には下記の専用ツールを使用します。起動シーンを参照する旧撮影ツールを王都用に使う場合は、別のチェックアウトで元の起動シーン設定を使用してください。

## 完成キャラクターの統合

標準では `scenes/frontend/characters/` の12シーンを `character_catalog.gd` から読み込みます。ホームはプレイヤー情報の `job_id` と `female`（未指定時はfalse）に従います。ツリーの男女切り替えは閲覧専用で、ホームの職業や外見を変更しません。

モデルの元コードは `character_playground/scripts/voxel_character.gd`、取り込んだ元コミットは `a027d27ac197ef1856e22b9207bb867e98efe6d7` です。Godotは別プロジェクトである `character_playground/` を親のインポート・書き出しから除外するため、モデル生成コードだけを `scripts/frontend/characters/voxel_character.gd` に内容を変えず複製しました。親のコードから練習用プロジェクト内のリソースを直接参照しません。テストでは元コードとのSHA一致も確認します。

`character_preview.gd` が元モデルの-Z正面をカメラ側へ回し、少し角度を付けて表示します。待機アニメーションと武器表示だけを制御し、入力・戦闘・移動の処理は含めません。ホームの所持武器は読み取りのみで、ツリーでは各職業の見本として武器を表示します。服装・防具は現時点では職業の基本造形で、装備名に応じた防具の外観交換は行いません。

元のキャラクターを更新した場合は、親の複製コードも同じ内容に更新し、モデルと表示のテストを実行してください。12シーンは職業と男女の指定だけなので再生成不要です。

## 別モデルへの差し替え

完成キャラクターの代わりに表示する場合は、`scenes/frontend/start_home.tscn` のルートを選び、インスペクターで次を設定してください。

- `character_scene`：ホーム中央の自分のキャラクターのPackedScene。
- `first_job_scenes`：第一職業カード用のPackedScene辞書。キーは `warrior` / `mage` / `scout` / `archer` / `cleric` / `artisan`。男女別に指定する場合は `mage_male`・`mage_female` のように末尾を付けます。男女別指定、職業共通指定、標準モデルの順に優先します。

シーンのルートは `Node3D`、足元は原点、正面は+Z、身長は約2 Godot単位を想定します。既存モデルの寸法・向きが異なる場合は、表示専用のラッパーシーンで調整してください。ゲームのPlayer、入力処理、HUD、カメラを含めない表示用モデルを渡します。各表示枠は独立したSubViewportとWorld3Dを持ち、モデル同士や王都と干渉しません。

## プレイヤー情報の接続

画面の `set_profile(snapshot: Dictionary)` にプレイヤーの表示情報を渡せます。画面はデータを読み取り、ゲーム状態や保存ファイルを書き換えません。サンプルの構造は `scripts/frontend/home_data.gd` にあります。実データ連携時は全項目を渡してください。

```gdscript
frontend.set_profile({
    "username": "プレイヤー名", "level": 12, "job_id": "warrior", "female": false,
    "exp": 340, "gold": 12345, "fame": "なし",
    "stats": {"筋力": 15, "耐久力": 23, "精神力": 31, "HP": 405,
              "MP": 63, "回復力": 17, "敏捷力": 28, "器用さ": 39},
    "skills": {"strong_strike": 4},
    "equipment": {"head": "兜", "body": "", "legs": "", "feet": ""},
    "owned_weapons": [{"name": "剣", "type": "剣", "rank": "コモン",
                       "equipped": true, "description": "武器の説明"}]
})
```

この例の「次のレベルまで」は `12 × 100 − 340 = 860 EXP` です。`exp` は累計でなく、現在レベル内の獲得EXPです。武器の `equipped` が真の項目をホームのメイン武器に表示します。第一職業とスキルIDは `home_data.gd` の対応を参照してください。複数武器の同時装備や装備変更はUIでは行いません。

## 確認・撮影

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tools/test_frontend.gd
# 描画可能なディスプレイ上で実行（headlessでは撮影不可）
godot --path . --audio-driver Dummy --script res://tools/capture_frontend.gd -- --page=home --output=/tmp/pvp-home.png
# 女性モデルの撮影、マウス・タッチ・男女切り替え・Escの動作確認
godot --path . --audio-driver Dummy --script res://tools/capture_frontend.gd -- --page=tree --female --exercise-input --output=/tmp/pvp-tree-female.png
```

テストはSTART遷移、第一6職の詳細と第二12職、武器なし・保有武器あり、8能力、EXP・所持金、サンプルからの情報差し替え、ナビゲーションの表示範囲、全12体の職業・男女・実メッシュ、男女切り替え、ホームの武器表示、待機アニメーション、モデル表示枠の独立性を確認します。実機での可読性や性能は未測定です。

新しい画面は既存HUDと別の日本語フォントを使います。文字を追加した場合のみ、Noto Sans CJKと任意の開発依存 `fonttools` を使って再生成できます。ゲームの実行には不要です。

```sh
python3 tools/subset_frontend_font.py --font /path/to/NotoSansCJK-Regular.ttc
```
