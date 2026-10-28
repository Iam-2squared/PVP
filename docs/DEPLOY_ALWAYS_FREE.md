# PVP Always Free 公開準備（未公開）

2026-10-28 JST。対象: `Iam-2squared/PVP`。本書は公開準備・運用手順であり、本番VM、DNS、Web公開、課金契約の実施記録ではない。

## 絶対条件

- **月額0円**。Oracle CloudはAlways Free（無料）アカウントのまま使用し、有料アカウントへの変更、有料リソース作成、無料トライアルクレジットによる有料VM利用を行わない。
- Oracle公式の新しいAlways Free文書によれば、Ampere A1の無料計算枠は合計 **2 OCPU / 12GB RAM**（月間1,500 OCPU時間/9,000GB時間）。無料対象と表示されたUbuntu ARM64 VMをホームリージョンに作成し、ブート/ブロックボリュームの無料枠にも収める。
- 外向き転送は公式に月10TBの無料枠があるが、容量不足でVMを作れない場合や、長期低負荷と判断され回収される場合がある。**24時間稼働の保証はない**。空きがないときに有料プランへ切り替えない。
- Oracleアカウント登録・本人確認・DNS名の取得は利用者自身で行う。SSH秘密鍵、Oracle資格情報、認証トークン、プレイヤーの `profiles.json` をGitHubに掲載しない。
- 既存Godot 4.6.3対戦処理は変更しない。コード上の受付上限64接続は64人分の性能を保証しない。小人数で試験公開する。

参照:
[OCI Always Free](https://docs.oracle.com/ja-jp/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) /
[OCI Free Tier](https://docs.oracle.com/ja-jp/iaas/Content/FreeTier/freetier.htm) /
[Godot dedicated server](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html) /
[Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)

## 1台で静的Webと対戦を配信

```text
PC・スマホ: https://<無料DNS名>/
    Caddy (OCI A1 VM、外部公開TCP 80 / 443)
      /    -> /srv/pvp/web              [Web export]
      /ws  -> 127.0.0.1:8910            [Godot WebSocket]
    Godot --headless (systemd: pvp-server)
      /opt/pvp/repo                     [既存ゲーム・server_kingdom.scn]
      /var/lib/pvp/profiles/profiles.json [プレイヤー成長・認証トークン]
```

利用する接続先は `wss://<無料DNS名>/ws`。**現行ゲームではホーム画面でこのURLを入力する**。自動設定は未実装。Vercelは必須でなく、既存Vercelプロジェクトの設定は変更しない。

## OCI コンソール（利用者本人が操作）

1. Free Tier登録。**Pay As You Goにアップグレードしない**。選択したホームリージョンでAlways Free対象の `VM.Standard.A1.Flex`（例: 2 OCPU/12GB、ブート50GB程度）を**1台のみ**作成する。
2. VCN・OSファイアウォールともに外部TCP 80/443を許可。22番SSHは管理者のIPに限定し、8910番は閉じたままにする。
3. 無料DNS名（例: DuckDNS）を用意し、VMの公開IPv4にAレコードを向ける。DNSの更新トークンをリポジトリに置かない。
4. OCI使用量と無料枠ラベル、ストレージ・転送の使用量を継続監視する。A1が `Out of host capacity` なら有料の代替は利用しない。

## VM にGodot 4.6.3を準備（Ubuntu ARM64）

これらの設定サンプルがリポジトリのmainにマージされた**後**、VMのSSHシェルから実行する想定。

```bash
sudo apt update
sudo apt install -y ca-certificates curl unzip git python3
uname -m  # aarch64
curl -fL -o /tmp/godot-arm64.zip \
  https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.arm64.zip
cd /tmp && unzip -oq godot-arm64.zip
sudo install -m 0755 Godot_v4.6.3-stable_linux.arm64 /usr/local/bin/godot-pvp
/usr/local/bin/godot-pvp --version
sudo groupadd --system pvp
sudo useradd --system --gid pvp --home-dir /var/lib/pvp --shell /usr/sbin/nologin pvp
sudo install -d -o pvp -g pvp -m 0700 /var/lib/pvp
sudo install -d -o pvp -g pvp -m 0755 /opt/pvp
sudo -u pvp git clone --depth 1 https://github.com/Iam-2squared/PVP.git /opt/pvp/repo
sudo -u pvp env HOME=/var/lib/pvp XDG_DATA_HOME=/var/lib/pvp \
  /usr/local/bin/godot-pvp --headless --editor --path /opt/pvp/repo --import
sudo cp /opt/pvp/repo/deploy/oci/pvp-server.service /etc/systemd/system/pvp-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now pvp-server
sudo systemctl status pvp-server --no-pager
sudo ss -ltnp | grep ':8910'   # localhostに限定されていること
```

本番導入前には公式配布物のチェックサム、対象PVPコミット、headless実行が正常であることを確認。更新時もmainの最新を無検証で自動反映させない。ログ: `sudo journalctl -u pvp-server -n 100 --no-pager`。

## Webの書き出しと公開

Web export templateを導入済みの開発機で確認済みコミットから生成する。Webの `index.pck` や `index.wasm` をVMの `/srv/pvp/web` に配置する。**サーバー専用シーン・セーブデータ・git履歴をWeb公開ディレクトリに入れない**。

```bash
mkdir -p build/web
godot --headless --editor --path . --import
godot --headless --path . --export-release Web build/web/index.html
python3 tools/serve_preview.py --directory build/web --prepare-only
```

VMに `sudo install -d -o ubuntu -g ubuntu -m 0755 /srv/pvp/web` を実行（SSHユーザーがubuntuの場合）。開発機から `rsync -av --delete build/web/ ubuntu@<VM_IP>:/srv/pvp/web/` でWeb成果物だけを転送する。

[Caddyの公式手順](https://caddyserver.com/docs/install)でCaddyを入れ、 `deploy/oci/Caddyfile.example` を `/etc/caddy/Caddyfile` へコピーし、`pvp-example.duckdns.org` を**自分のDNS名**に置換する。

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy
```

Caddyは公開DNSとポート80/443が正しい場合にHTTPS証明書とWSSプロキシを提供する。既存 `serve_preview.py` は開発用であり、公開中のHTTP常駐には使用しない。配布用のgzipサイドカーファイルはCaddy `precompressed gzip` で配信する。

## 公開前の必須ゲート

- PC・iPhone・AndroidからHTTPSでスタート画面を表示し、WASM/PCKのMIME/圧縮を確認。
- 別プロフィールの2人が同じ `wss://<DNS名>/ws` に入場。描画・移動・射撃・撃破・EXP・復帰・帰還を確かめる。
- サーバー再起動後にレベル/EXP/未使用ポイント・クライアントIDが維持される。
- CPU/メモリ/通信量/ディスクを観測。スマホ物理実機のFPS・発熱・画面操作を計測する。
- `docs/battle-concurrent-proof.json` には同時2ブラウザの描画テストが不合格になった記録がある。通信JOINの成功と2人対戦全体の成功を混同しない。

## 保存・バックアップと未解決事項

正本 `/var/lib/pvp/profiles/profiles.json` は更新・再起動でも消さず、認証トークンを含むため公開しない。`deploy/oci/backup-profiles.sh` は同じVM内でJSON整合性を検証した**ローカルコピーのみ**作る。例: `sudo -u pvp bash /opt/pvp/repo/deploy/oci/backup-profiles.sh`。**VMが回収されればローカルコピーも失う可能性がある**。公開前にOCI Always Freeのボリュームバックアップ・Object StorageなどでVM外のバックアップ先を決め、復元テストを実施する（構成・課金対象ラベルを事前確認）。

現在のプレイヤー認証は端末に保存されたIDとトークンによる。端末を変える・ブラウザデータを削除すると復旧しにくい。アカウント復旧機能ができるまでは利用者に制約を表示する。

## 作業状態

- [x] Godot 4.6.3 Web/サーバーの既存実装を調査
- [x] OCI Always Free向けのCaddy/systemd/バックアップの設定例と手順
- [ ] Oracleアカウント作成、無料VM作成（本人操作）
- [ ] DNS・HTTPS・Web配信・WSSを本番環境で実証
- [ ] オフVMバックアップ・復旧テスト
- [ ] スマホ実機と多人数負荷の公開前Gate
- [ ] 明示的な公開判断

本PRで**本番公開・契約・有料リソース作成・mainマージは行わない**。
