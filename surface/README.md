# Surface Pro 7

Surface Pro 7用のNixOS設定です。GNOMEをタブレット向けに調整し、次を有効にします。

- `linux-surface`、IPTSタッチ・ペン、画面回転センサー
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
自動表示されます。
