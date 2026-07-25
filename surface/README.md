# Surface Pro 7

Surface Pro 7用のNixOS設定です。GNOMEをタブレット向けに調整し、次を有効にします。

- `linux-surface`、IPTSタッチ・ペン、画面回転センサー
- 電源ボタンを押したときのサスペンド
- 左側に常時表示するGNOMEドック
- GNOME画面キーボード
- IBus + Mozc UTによる日本語入力
- 200%表示スケール
- Krita

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

<!-- TODO: nixpkgsがMutter 50.3以降になったら互換パッチとこの説明を削除する。 -->
GNOME 50.2のMutterはtext-input-v3のversion 2を実装した際、version 1クライアントが
画面キーボードを再表示するために使っていた互換動作を削除しました。GTK 4.22はまだ
version 1を使うため、この構成ではMutterへその互換動作を戻すパッチを適用します。

## 既知の制限

BitwardenのFlatpak版では、入力欄をタッチしてもGNOMEの画面キーボードが自動表示
されません。Electron/ChromiumとGNOME Waylandの入力プロトコル連携に起因するため、
この構成にはBitwarden固有の回避処理を含めません。入力時は上部パネルのキーボード
ボタンを使用してください。
