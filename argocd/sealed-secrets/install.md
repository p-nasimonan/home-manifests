# Sealed Secrets のセットアップ

`sealed-secrets` はクラスタ内で Secret を暗号化・復号化するための Kubernetes コンポーネントです。平文の Secret を Git に保存する代わり、`SealedSecret` として暗号化してコミットできます。

## インストール

1. **sealed-secrets controller をクラスタにインストール**

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

2. **`kubeseal` CLI をローカルにインストール**

```bash
# macOS (Homebrew)
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/

# または npm 経由（Node インストール済みなら）
npm install -g kubeseal
```

3. **インストール確認**

```bash
kubeseal --version
```

## 使い方（基本フロー）

### ステップ 1: 生の Secret を作成

```bash
cat > my-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: my-secure-password-123
EOF
```

### ステップ 2: Secret を暗号化して SealedSecret を生成

```bash
kubeseal -f my-secret.yaml -w my-sealed-secret.yaml
```

### ステップ 3: 生の Secret を削除し、SealedSecret をコミット

```bash
rm my-secret.yaml
git add my-sealed-secret.yaml
git commit -m "Add sealed secret for my-secret"
```

### ステップ 4: Argo CD で同期

SealedSecret が Argo CD で同期されると、sealed-secrets controller が自動で復号化して Secret リソースを作成します。

```bash
# 確認
kubectl get sealedsecrets
kubectl get secrets
```

## 暗号化キーの管理

sealed-secrets のキーペアはクラスタ内に保存されます。キーを復号化するには `sealed-secrets` controller が必要です。

**キーのバックアップ（重要）**

```bash
# 秘密鍵をバックアップ
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml
```

**キーの復元**

```bash
kubectl apply -f sealed-secrets-key.backup.yaml
```

## lefthook との統合（オプション）

ローカルで `pre-commit` 時に自動暗号化したい場合、以下を `lefthook.yml` に追加：

```yaml
pre-commit:
  commands:
    check-secrets:
      run: npm run check:secrets
    # 以下のコマンドで `secrets/` フォルダ内の平文 Secret を自動暗号化（オプション）
    # seal-secrets:
    #   run: |
    #     for file in apps/*/secrets.yaml; do
    #       if [ -f "$file" ]; then
    #         kubeseal -f "$file" -w "${file%.yaml}.sealed.yaml" && rm "$file"
    #       fi
    #     done
```

## トラブルシューティング

**Q: 既存の Secret を SealedSecret に変換したい**

```bash
# クラスタから Secret を取得
kubectl get secret my-secret -o yaml > my-secret.yaml

# 生のデータを stringData に変換してから kubeseal
# （注意: 平文データを扱うため、ローカルのセキュアな環境で実行）
kubeseal -f my-secret.yaml -w my-sealed-secret.yaml
```

**Q: 異なるクラスタで使用する SealedSecret**

各クラスタが異なる encryption キーを持つため、一つのクラスタで暗号化した SealedSecret は別クラスタでは復号化できません。複数クラスタ運用の場合は、各クラスタ用に SealedSecret を作成してください。

## 参考

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [公式ドキュメント](https://sealed-secrets.dev/)
