# Windows PCから無料でPVPを一時公開する

対象: Godot 4.6.3版 PVP（王都セレシア）。PCが起動している間だけ友達とWebブラウザで対戦するためのランチャー。Cloudflare Quick Tunnelによる少人数テスト向けで、24時間稼働が保証される本番ホストではない。

## 使い方（Windows）

1. PVPの最新コードをPCに取得する（clone済みならGitで最新mainをpull）。
2. リポジトリ直下の Start-PVP-Public.bat をダブルクリック。
3. 初回のみ、必要ならGodot 4.6.3・Web Export Templates、Caddy、cloudflaredを公式リリースから取得。Web Export Templatesはサイズが大きいため実行前に確認を表示。
4. 画面に https://xxxx.trycloudflare.com が出たら、そのURLを友達に送る。ローカルブラウザも自動的に開く。
5. 終わるときは起動ウインドウで Enter。別に停止するときは Stop-PVP-Public.bat をダブルクリック。PCのスリープ・シャットダウン中は公開されない。

Cloudflareの公開URLで開いた場合、Godotホームの「プレイヤー設定」は wss://xxxx.trycloudflare.com/ws を自動設定する。ほかのWebホスト・ネイティブ・LAN設定はそのまま。

**公開URLは毎回変わる。** Godot Webのブラウザー保存領域はオリジンごとに別になるため、以前のログイン情報は新しいURLに自動で引き継がれない。次の復帰コードを必ず利用する。

## キャラクター引き継ぎ（重要）

初回の対戦接続が成功したらホームの「プレイヤー設定」から「復帰コードを表示・コピー」。個人用の安全な場所（パスワードマネージャー等）に保存する。

次回、新しく発行した公開URLを開き、**最初のバトルへ入る前に** 「プレイヤー設定」→「復帰コードで以前のキャラクターに戻る」で自分のコードを入力する。その後の接続で、同じPCの保存データに照合して前回のEXP・レベル・能力値に戻る。

- 復帰コードはプレイヤーIDとサーバー認証トークンを含む秘密情報。人に見せない。SNS・GitHub・スクリーンショットに載せない。
- 新URLで先に別のユーザーを登録した場合、同じURL内の登録済みIDは自動上書きしない。接続前に復帰コードを設定する。
- サーバー側の profiles.json が削除・破損すると、復帰コードだけでは成長を取り戻せない。
- 復帰コードの貼り付けは本人が手動で実行する。復帰コードはリンクのクエリやログに載せない。


## 2026-10-28: Web export成功後のCloudflare公開URL取得・停止エラー

Windows実機でGodotのWeb書き出し・gzip準備・Caddy設定確認・Godot/Caddy/cloudflared起動は成功したものの、Cloudflareが期限内に公開URLを返さず、旧停止スクリプトで `System.Object[]` の `pid` を整数へ変換できず失敗した記録がある。**公開成功ではない。**

対策:
- `cloudflared tunnel --url http://127.0.0.1:18080` の公式Quick Tunnel構文を使う。
- URLが取得できない場合、最初の通信ログを表示してから `--protocol http2` (TCP 7844) でも一度試す。通常は自動でQUIC/HTTP2を選択するが、ネットワーク制限がある場合の切り分けのため。
- 二度とも失敗した場合は、`.pvp-local/logs/cloudflared.err.log` / `cloudflared.out.log` の末尾をコンソールへ表示。**ログ中にURL、秘密の資格情報などがないか確認してから共有すること。**
- 停止側は旧形式の多重JSON配列も解釈して、実行パスと開始時刻が一致する追跡プロセスだけを停止。途中で失敗しても保存データを削除しない。
- 修正版を導入したら、**起動前に `Stop-PVP-Public.bat` を一度実行**して、前回の3プロセスの残留を解消する。ポート8910/18080を開きっぱなしにして再起動しない。
- `~/.cloudflared/config.yml` / `config.yaml` を使っている場合、Quick Tunnelの動作と衝突するケースがある。自動で削除・改名はせず、画面で案内する。
- 社内/学校Wi-Fi、Windowsのセキュリティ製品、ルーター、プロバイダがCloudflare宛のTCP/UDP 7844を塞いでいるとQuick Tunnelが接続できない。ログから判断し、必要なら別ネットワークで切り分ける。ポートの外部公開や有料クラウドへの移行は要求しない。


## 2026-10-28: Cloudflareは接続済みなのにURLが検出されないケース

実PCログではDNS・QUIC・HTTP/2・Cloudflare APIのprecheckが全てPASSし、`Registered tunnel connection` が出た。しかし起動スクリプトがURLを認識せず中断していた。公開URLは接続登録よりも先にCloudflareログへ出るため、表示した末尾30行には含まれない場合がある。

旧版ではPowerShellが `Start-Process -RedirectStandardError` で作成したファイルを、稼働中に `File.ReadAllText` で読もうとし、アクセスエラーを無視していた。これがURL未検出の有力な原因だが、利用者PCでの厳密な原因確認はまだ行っていない。

修正版:
- Cloudflareの `--logfile` により、標準エラー出力とは別のログを発行させる（`.pvp-local/logs/cloudflared-primary.log`、再試行時は `cloudflared-http2.log`）。
- Windowsでファイルが書き込み中でも、共有読み取り権限を付けて全文を解析する。古いURLを誤検出しないよう再実行前のログは `.previous` に退避。
- 起動に失敗した場合はログの先頭と末尾を表示する。ログ全体を確認するには次のPowerShellを使う（**公開URLだけを抽出**）:

```powershell
Get-ChildItem "$HOME\PVP\.pvp-local\logs" -Filter "cloudflared-*.log" |
    Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches |
    ForEach-Object { $_.Matches.Value } | Select-Object -Unique
```

URLがログにあるだけでは、そのURLが今も稼働中とは限らない。必ず起動ウインドウで公開状態を確認し、実際にブラウザーから表示できることを確かめる。

## 構成

    HTTPS: Cloudflare Quick Tunnel（毎回ランダムなホスト）
      -> http://127.0.0.1:18080（CaddyでWeb配信）
      -> /ws -> 127.0.0.1:8910（Godot HeadlessのWebSocket）
    Godot user://battle_server/profiles.json（既存の保存先）

- 8910番・18080番は127.0.0.1だけで待受け。ルーターのポート開放・Windows受信許可・有料ドメイン・クラウド契約は不要。
- CloudflareからはHTTPS/WSS。URLを知っている誰でもテストゲームへアクセスできる。知人同士から始める。一般公開向けのセキュリティ監査は未実施。
- Godotの標準ユーザー保存先を変更せず起動。既存ファイルがあれば起動前に .pvp-local/backups/ へローカルコピーを追加する。
- .pvp-local/ はGit除外対象。公式配布のバイナリ、Web書き出し、ログ、実行中のPID、バックアップを保存する。
- 攻撃判定・EXP・同時接続受付上限は既存実装。64はコード上の上限であり、64人での正常動作を意味しない。

## 初回の注意・トラブル

- Windows 64bit (x86-64) を想定。Godot 4.6.3本体と同バージョンのWeb Export Templatesが必要。見つからなければ公式リリースからダウンロードする。テンプレートの大型ダウンロードは確認が表示される。
- 2026-10-28のWindows初回公開で、旧ランチャーが `web_release.zip` / `web_debug.zip` のみを配置していた問題を修正した。現行のWeb presetは `variant/thread_support=false` なので **`web_nothreads_debug.zip` と `web_nothreads_release.zip` の両方**が必要。修正後に必要ファイルが不足している場合は、初回だけ公式約1.26GBテンプレートパッケージの**再ダウンロード確認**が出る。古いファイルやセーブデータは削除しない。ダウンロード後は必要な2ファイルだけを取り出し、次回以降は再取得しない。
- 初回の素材インポート・Web書き出し・ダウンロードにはネット回線と時間が必要。次回以降は必要ツールをキャッシュする。
- ツール取得元はGodot・Caddy・Cloudflareの公式GitHub Releaseのみ。失敗時は起動を中断しエラーを表示する。
- 8910・18080ポートが占有されている場合は使用中のプロセスを確認。Stop-PVP-Public.bat は記録済みの自分のプロセスに限り停止する。
- ログ: .pvp-local/logs/。他人にログを送る前に公開URL・個人情報を確認し、復帰コードを貼らない。
- レンダリング/通信性能は端末によって異なる。物理スマホでのFPS・安定性は未検証。
- Godot Web Exportはステージングディレクトリに生成し、完成を確認してから前回成果物と切り替える。
- 失敗したときにプレイヤーデータを削除しない。

## 料金・稼働上の限界

Cloudflare Quick Tunnelはアカウントなし・無料で開発用の一時HTTPS URLを提供。テスト用途で稼働保証はない。公開URLは再起動のたびに変わり、リクエスト制限がある。PCとネット回線が起動中のときだけ利用でき、電気代・通常通信費は別。

参考公式資料:
- https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
- https://developers.cloudflare.com/cloudflare-one/faq/cloudflare-tunnels-faq/
- https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html

## 検証状態

- GitHubには起動・停止スクリプト、接続先自動設定と復帰コード、回帰テストを追加。
- **Windows実機での起動・外部からのWSS接続・スマホでのゲーム操作は未検証**。本番公開済みと断定しない。
- ローカルテスト: godot --headless --path . --script res://tools/test_frontend_battle.gd
