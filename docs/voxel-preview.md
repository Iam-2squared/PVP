# 王都セレシアのボクセル3Dプレビュー

更新日：2026-10-27。無料の Godot 4.6.3 で開ける、スマートフォン横画面を想定した一人称の王都試作です。城壁・王城・城下町を含む `town` 段階の生成と物理移動の検証を完了しました。オンラインPvP、NPC、職業や成長の仕組みは今後の実装対象です。

## 造形と制作範囲

建築は共通の 0.5 m グリッドで作り、細い看板・紐・食器などを小さな立体部品で補っています。画像の王都配置を土台に、北側に王城、南側に庭園と城下町を置く構成です。実在建築と公式写真の観察は [建築参考資料](architecture-references.md) に記録しています。

| 場所 | 内容 |
| --- | --- |
| 王都の外周 | 幅 320 m の正八角形。壁厚 7 m、歩廊の高さ 24 m、有効幅 5 m。 |
| 城壁の設備 | 角塔 8、東西南北の門 4、門脇の塔 8、射撃台 12、内側の階段 4、覆い付きの張り出し防御回廊 3。歩廊と塔・門楼を移動できる。 |
| 王城 | 東京ディズニーランドのシンデレラ城の縦長の輪郭を主な参考にした独自設計。最高点 94 m。低い前門、急勾配の屋根、段違いの中塔、細い主塔を重ねる。 |
| 王城内部 | 用途の異なる 21 室。床の高さは 3・9・15・21・27・33 m。大階段、玉座の間、回廊、図書室、食堂、厨房、評議室、執務室、寝室、衛兵の部屋などを配置。 |
| 王城の細部 | 図書室の書籍と文具、食堂の皿と杯、厨房の炉、寝台のカーテンなど、部屋の用途に合わせた小物。 |
| 城下町 | 住宅・小店舗等 304 棟と、大型の冒険者ギルド・酒場・教会の 3 棟。市場、鍛冶屋、訓練場、整形式の庭園・公園を配置。街で入れる住宅・公共施設は計 11 か所。 |
| 街路と細部 | 35 本の街路と、主街路・細い路地・小広場で変化する密度。建物をつなぐ紐、旗、洗濯物、店の看板、樽など。屋台 12 台の屋根と支柱は建築のボクセル形状に含め、遠景でも残る。 |

地面の上端は全域で Y=2 m。城内は公園・庭園を除いて共通の石畳とし、城下町の住宅・公共施設の一階でも同じ地面を床に使います。目地は Shader で表し、城下町の敷地ごとに重なった床板を置きません。王城は基壇と高さ 3 m からの専用の床を持ちます。基礎となる地面全体は 20 三角形・2 メッシュ・1 個の BoxCollider です。

城外を含む約 640 m 四方の地面は平らです。城外は山岳・海・砂漠・草・岩を配置していない更地です。周辺地形の将来案は README のゲーム構想に残しています。

## プレビュー画像

![王都全体](voxel-overview.png)

![南門と城壁](voxel-gate.png)

![王城の外観](voxel-castle.png)

![城下町の路地](voxel-town.png)

![王城の図書室](voxel-library.png)

## 起動と操作

Godot 4.6.3 でリポジトリの `project.godot` をインポートし、**F5** でメインシーンを実行します。追加ライブラリや Blender は起動に不要です。

| 操作 | PC | タッチ端末 |
| --- | --- | --- |
| 移動 | WASD / 矢印キー | 左のスティック |
| 視点 | 画面クリック後にマウス | 右側の空白をドラッグ |
| 走る | Shift | — |
| 跳ぶ | Space | ジャンプボタン |
| 見学場所を順に切り替える | N | 右上の「見学先」ボタン |
| 全体図と歩行を切り替える | M | 右上の「全体図」ボタン |
| マウスを解除する | Esc | — |
| 仮の開始位置へ戻る | R | — |
| 開発用の統計表示 | F3 | — |

0.5 m 程度の段差は歩いて登れます。全 13 か所の見学先を切り替えて王城前、広間、図書室、街の施設などへ移動でき、全体図から建物と道の配置を確認できます。

## 軽量化と計測

- ボクセル一個ずつに Node や Cube を作らず、外へ露出する面だけを生成する。
- 同色・同方向・同じ陰影条件の隣接面を結合する greedy mesher を使い、局所的な陰影は頂点色へ焼き込む。
- 建築を 32 m ごとの空間区画へ分ける。各生成成分は頂点色のパレット材質を一つ使い、画面外の区画を描画対象から外す。
- 形状と衝突判定を制作時に生成し、圧縮済みシーンへ保存する。`generated/kingdom.scn` と `generated/parts/` に分割し、実行時に全ボクセルを作り直さない。
- 王城内部は階や部屋の成分へ分け、城の近くで現在地に近い階を表示する。内装はリアルタイムの影を落とさない。
- 細い小物は CPU で作った ArrayMesh にまとめ、表示距離を 90 m に制限する。小物には影と衝突判定を付けない。
- 石畳の目地は追加のブロックや画像テクスチャを使わず描画する。追加購入のモデルや素材には依存しない。

`town` 段階の保存済み形状は次のとおりです。内訳は [generated/world_metrics.json](../generated/world_metrics.json) から集計しています。

| 成分 | 保存済み三角形数 | 補足 |
| --- | ---: | --- |
| 城壁・塔・門楼 | 345,500 | 116 区画 |
| 王城外観 | 158,426 | 23 区画 |
| 王城内部 | 34,094 | 6 成分・48 区画 |
| 王城の細かい小物 | 40,152 | 5 成分・3,346 個の小ブロックを 20 区画へ集約 |
| 城下町の建築・設備 | 533,492 | 81 区画。屋台の屋根・支柱を含む |
| 街の細かい小物 | 345,408 | 28,784 個の小ブロックを 73 区画へ集約 |
| 地面 | 20 | 2 メッシュ・1 個の BoxCollider |

圧縮済みシーンは 19 個の分割成分と親シーンを合わせて **19,467,476 bytes（約 18.57 MiB）** です。JSON の `total_scene_bytes` に相当します。上表の三角形数は合計 1,457,092 で、保存している全形状の量です。毎フレーム描画する量は、視野、距離、王城の階の表示切り替えによって変わります。draw calls は影の描画パスの影響も受けるため、F3 または撮影ツールの出力で視点ごとに確認します。

スマートフォン実機の FPS・メモリ使用量は未測定です。ブラウザのモバイル画面エミュレーションや制作環境の描画数とは区別します。

## 造形を変更する場所

| ファイル | 内容 |
| --- | --- |
| `scripts/voxel/walls.gd` | 城壁、角塔、門楼、歩廊、階段、射撃設備 |
| `scripts/voxel/palace.gd` | 王城の外観、部屋、床、階段、移動経路 |
| `scripts/voxel/palace_details.gd` | 王城の部屋ごとの細かい家具・小物 |
| `scripts/voxel/town.gd` | 街区、建物、道、公共施設、公園の配置 |
| `scripts/voxel/house_builder.gd` | 住宅の形状と一部の入れる部屋 |
| `scripts/voxel/civic_buildings.gd` | ギルド、酒場、教会の建築と一階内部 |
| `scripts/voxel/detail_builder.gd` | 紐、洗濯物、旗、看板、樽などの小物 |
| `scripts/voxel/terrain.gd` | 平らな地面、共通の石畳と目地 |
| `scripts/voxel/volume.gd` / `mesher.gd` | 制作時のボクセル配置、面の結合、陰影 |
| `scripts/voxel/factory.gd` / `world.gd` | 成分の組み立て、見学先と表示管理 |
| `scripts/voxel_preview.gd` | 生成済みシーンの読み込み、光と空 |
| `scripts/player_controller.gd` / `hud.gd` | 一人称移動、タッチ操作、全体図、見学UI |

通常の見学には同梱の生成済みシーンを使うため、再生成は不要です。造形コードを変更した場合は、リポジトリのルートで制作段階を明示して再生成します。

```sh
godot --headless --path . --script res://tools/bake_voxel_world.gd -- --stage=town
```

`--stage=walls` は地面と城壁、`--stage=palace` は王城まで、`--stage=town` は城下町を含む段階です。再生成後に F5 で開き直してください。

## 検証

生成済みシーンに対し、共通形状と操作、城壁の構成、王城の部屋・階段・経路、街の入口・通路を分けて検証します。物理移動の再現性を保つため `--fixed-fps 60` を付けます。

```sh
godot --headless --path . --fixed-fps 60 --script res://tools/test_voxel_world.gd
godot --headless --path . --fixed-fps 60 --script res://tools/test_fortress.gd
godot --headless --path . --fixed-fps 60 --script res://tools/test_palace_routes.gd
godot --headless --path . --fixed-fps 60 --script res://tools/test_town_routes.gd
```

城下町を含む最終シーンで、次の 4 本すべてを通過しました。

| 検証 | 結果 |
| --- | --- |
| 共通形状・操作 | 73 項目 PASS |
| 城壁・塔・門・射撃設備 | 25 項目 PASS |
| 王城の部屋・階段・歩行 | 115 項目 PASS、全 13 経路を歩行 |
| 街路・施設入口・公共施設内部 | 64 項目 PASS、街路と公共施設内部の経路を歩行 |

Web 版を配信した状態で、[browser_smoke.py](../tools/browser_smoke.py) により Chromium のデスクトップ画面とモバイル横画面を確認できます。Python の Playwright、Pillow、Chromium が必要です。

```sh
python3 tools/browser_smoke.py --url http://127.0.0.1:8080/ --output captures
```

起動、実際の 3D 描画、移動、全体図、N キーまたはタッチによる見学先の切り替え、致命的な JavaScript / GDScript エラーを検査します。街や王城を歩き通す検証は Godot 側の経路テストで行います。モバイル画面のエミュレーションは実機の速度測定ではありません。

最終の `town` 版で、Chromium の PC 1280×720 とモバイル横 844×390 の両方が合格。前進、全体図から歩行への復帰、見学先の2回の切り替えを確認し、JavaScript・GDScript・コンソールのエラーは0件でした。モバイル側は実際のタッチイベントで操作しています。[Web検証結果](web-smoke-results.json)。

## スクリーンショット

実際に画面を描画できる環境で実行します。撮影には `--headless` を付けません。

```sh
godot --path . --audio-driver Dummy --script res://tools/capture_preview.gd -- --overview --hide-hud --output=/tmp/voxel-overview.png
godot --path . --audio-driver Dummy --script res://tools/capture_preview.gd -- --tour=palace_front --hide-hud --output=/tmp/voxel-castle.png
godot --path . --audio-driver Dummy --script res://tools/capture_preview.gd -- --tour=palace_library --hide-hud --output=/tmp/voxel-library.png
```

`--position=x,y,z`、`--yaw=角度`、`--pitch=角度` で歩行視点を指定できます。俯瞰の構図は `--camera-position=x,y,z`、`--camera-target=x,y,z`、`--overview-size=幅` で調整できます。

## ブラウザ版の作成

Godot 4.6.3 と同じバージョンの Web export template を導入し、リポジトリのルートで実行します。

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python3 tools/serve_preview.py --directory build/web --port 8080
```

`http://127.0.0.1:8080/` を開きます。HTML の直接ダブルクリックではなく HTTP で配信してください。同じ LAN の端末から試す場合は、配信コマンドに `--bind 0.0.0.0` を加え、PC の LAN アドレスとポートへアクセスします。

[download_web_templates.py](../tools/download_web_templates.py) は公式テンプレートの Web 部分だけを取得する補助ツールです。対象の Godot バージョンを確認して使用してください。

## 外部3Dツール向けの書き出し

```sh
godot --path . --audio-driver Dummy --script res://tools/export_model.gd -- --output=res://build/selesia.glb
```

GLB 書き出しにも実描画できる環境が必要です。出力は形状確認・外部編集向けで、衝突判定、カメラ、HUD、ゲームの処理は含みません。Godot 固有の石畳 Shader の目地は GLB では単色の材質へ置き換わります。GLB を編集しても生成コードへ自動反映されません。

## 使用素材

建築、地面、小物の形状と配色はプロジェクト内で生成しています。追加の素材購入は不要です。外部の参考写真や既存作品のモデルは転載していません。

UI フォントは OFL の Noto Sans CJK を必要文字に絞ったものです。ライセンスは [NOTO-LICENSE.txt](../assets/fonts/NOTO-LICENSE.txt) を参照してください。
