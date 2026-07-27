# Surface Pro 7

Surface Pro 7用のNixOS設定です。GNOMEをタブレット向けに調整し、次を有効にします。

- `linux-surface`、IPTSタッチ・ペン、画面回転センサー
- 電源ボタンを押したときのサスペンド
- 電源ボタンと音量上ボタンの同時押しによる全画面スクリーンショット
- TouchUpによるジェスチャーナビゲーション、通知・画面キーボード操作
- 自動非表示の下部GNOMEドック
- GNOME画面キーボード
- IBus + Mozc UTによる日本語入力
- 200%表示スケール
- Loupeによる画像表示
- SushiによるNautilusのファイルプレビュー
- Krita
- Bitwarden Desktop
- rcloneによるProton Driveマウント

## インストール後の適用

インストーラーが生成したハードウェア設定には、実機のパーティションUUIDが含まれます。
初回の切り替え前に、必ずそのファイルをこのディレクトリへコピーしてください。

```console
cd /path/to/dotfiles/surface
cp /etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
sudo nixos-rebuild switch --flake .#surface
```

`hardware-configuration.nix`をコピーせずに切り替えると、ルートファイルシステムを
マウントできないため起動できません。

ログイン後、画面右上の入力ソースから「日本語 (Mozc)」を選びます。物理キーボードでは
通常 `Super+Space` でも切り替えられます。画面キーボードはテキスト欄をタップすると
自動表示されます。上部パネルのキーボードボタンでも表示・非表示を切り替えられます。
入力メソッドの環境変数はログイン時に決まるため、設定の適用後は一度ログアウトして
ログインし直してください。

TouchUpのナビゲーションバーはGNOMEのタッチモードで表示されます。画面下端からの
ジェスチャー、通知のスワイプ操作、画面キーボードのスワイプ終了、回転ロック時の
フローティング回転ボタンを有効にします。クリップボード内容を読むOSKのクイック
ペースト機能は無効にします。

## IPTSDのペン・タッチ排他パッチ

`patches/iptsd-stylus-release-delay.patch` は、`DisableOnStylus`によるペン使用中の
タッチ無効化を次の2点で補強します。

- `StylusReleaseDelay = 300`により、ペンが近接範囲を離れてから300ミリ秒間は
  タッチを再有効化しません。ペン先を一度離して再び近づける短い間に、手のひらが
  2接点として漏れてKritaの2本指Undoなどを誤作動させることを防ぎます。
- IPTSD 3.1.0は、ペンが非近接であることを示す通知でもタッチを強制解除し、接点の
  追跡状態を消去します。非近接通知がタッチ中に繰り返されると、1回の2本指操作が
  複数の独立した操作へ分断されます。パッチでは、ペンが現在近接中、または近接から
  離れた瞬間だけタッチを解除し、非近接通知の反復では解除しません。

この変更はタッチ接点のサイズやパーム判定閾値を変更するものではありません。
ペンを離してからタッチ操作が可能になるまで最大300ミリ秒の待ち時間が発生します。
後者のIPTSD不具合は
[upstream Issue #218](https://github.com/linux-surface/iptsd/issues/218)
で報告しています。

## Proton Drive

この構成ではrcloneのProton Drive backendを使います。認証情報はNixでは管理せず、
実機で `rclone config` に手入力します。Proton Driveの暗号鍵がまだ作られていない
アカウントではrcloneの認証が失敗するため、先にブラウザからProton Driveへ通常ログイン
しておきます。

設定適用後、次を実行して `protondrive` というremoteを作成します。

```console
rclone-protondrive-config
```

プロンプトでは新規remoteを作成し、名前に `protondrive`、storage typeに
`protondrive` を指定して、Protonアカウント、パスワード、必要なら2FAコードを入力します。
疎通確認は次の通りです。

```console
rclone lsd protondrive:
```

`~/.config/rclone/rclone.conf` に `protondrive` remoteが存在すると、ログイン時にuser
service `rclone-protondrive.service` が `~/ProtonDrive` へマウントします。すぐに反映する
場合は次を実行します。

```console
systemctl --user restart rclone-protondrive.service
journalctl --user -u rclone-protondrive.service -f
```

<!-- TODO: nixpkgsがMutter 50.3以降になったら互換パッチとこの説明を削除する。 -->
GNOME 50.2のMutterはtext-input-v3のversion 2を実装した際、version 1クライアントが
画面キーボードを再表示するために使っていた互換動作を削除しました。GTK 4.22はまだ
version 1を使うため、この構成ではMutterへその互換動作を戻すパッチを適用します。

## TODO

Type Coverのタッチパッド操作までモバイルOS風に揃える場合は、
`pkgs.gnomeExtensions.touchpad-gesture-customization`の導入を検討します。

## 既知の制限

Bitwardenは、入力欄をタッチしてもGNOMEの画面キーボードが自動表示
されません。Electron/ChromiumとGNOME Waylandの入力プロトコル連携に起因するため、
この構成にはBitwarden固有の回避処理を含めません。入力時は上部パネルのキーボード
ボタンを使用してください。
