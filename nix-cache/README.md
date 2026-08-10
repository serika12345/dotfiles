# macOS Nixバイナリキャッシュ

NixOSホストは読取り専用のHTTPバイナリキャッシュを公開します。書込み認証には、
Bitwarden SSH Agentに登録済みのNixOS管理鍵を使用します。キャッシュ用アカウントでは
同じ鍵でもNix storeプロトコルだけを実行でき、シェルや転送は利用できません。公開署名鍵は
各flakeが独立して評価できるよう、次のローカルファイルにそれぞれ置いています。鍵を
ローテーションするときは、対応する値をまとめて更新してください。

- `nixos/macos-nix-cache-public-key`
- `nix-darwin/macos-nix-cache-public-key`

通常の`nix build`はこのキャッシュを**読むだけ**で、成果物を自動公開しません。公開したい
依存関係rootだけを、次の汎用コマンドで明示的にビルド・公開します。

```sh
nix-cache-build .#dependencies
```

このコマンドは指定した出力のclosure全体をビルドし、Bitwarden CLIで対話的にvaultをunlock
してから、署名・NixOSへの送信を行います。ビルド一時ディレクトリやログは送信されません。
送信後は`bw lock`でCLI vaultを再ロックし、一時的に作成した秘密鍵ファイルを削除します。

最初に、BitwardenへLoginアイテムとしてキャッシュ署名鍵を登録します。秘密鍵全体をpassword
欄へ保存し、作成後に得たアイテムUUIDを次のコマンドで登録してください。

```sh
nix-cache-configure-bitwarden BITWARDEN_ITEM_UUID
```

UUIDだけが`~/.config/nix/macos-nix-cache-bitwarden-item-id`へ権限`0600`で保存されます。秘密鍵
そのものやBitwardenのセッショントークンは保存しません。既存のローカル署名鍵は、Bitwarden
からの公開と復元を確認してから手動で削除してください。

Bitwarden CLIは最初に一度だけ`bw login`でログインします。その後の`nix-cache-build`は毎回
`bw unlock`を対話的に実行し、処理の最後に`bw lock`します。

サーバーの空き容量が20 GiB未満になると、新規アップロードを拒否してNixOSのシステム
ボリュームを保護します。危険な経過日数ベースの削除は行わず、キャッシュを削減する場合は
必要な成果物を記録・検証したうえで、新しい世代のキャッシュディレクトリへ置き換えてください。

適用順はNixOS構成、次にnix-darwin構成です。最初の公開を検証するには、
`nix-cache-build .#dependencies`を実行し、安全な場合に限ってローカルstoreから成果物を除去した後、
通常の`nix build --refresh .#dependencies`を実行します。HTTPキャッシュはプライベートLAN限定ですが
認証はありません。LAN上のすべてのクライアントに読取りを許可できない限り、プロプライエタリな内容や
秘密情報をNix成果物へ含めないでください。
