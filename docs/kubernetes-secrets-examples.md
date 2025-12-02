# Kubernetes Secret Types と GitOps での管理

このリポジトリでは **sealed-secrets を使用して Secret を安全に Git 管理** しています。以下の内容を参照してください。

## Secret リソースのタイプ

### 1. `Opaque` (デフォルト) — 任意のキーバリューペア
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-password
  namespace: default
type: Opaque
stringData:
  username: admin
  password: secure-password-123
```

### 2. `kubernetes.io/dockercfg` — Docker registry 認証
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: docker-registry-secret
type: kubernetes.io/dockercfg
stringData:
  .dockercfg: '{"auths":{"ghcr.io":{"auth":"base64-encoded-credentials"}}}'
```

**用途**: `imagePullSecrets` でコンテナイメージをプルするときの認証。

### 3. `kubernetes.io/dockercfg-json` — Docker config.json 形式
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: docker-json-secret
type: kubernetes.io/dockercfg-json
stringData:
  .dockerconfigjson: '{"auths":{"ghcr.io":{"auth":"base64-encoded-credentials"}}}'
```

### 4. `kubernetes.io/basic-auth` — Basic 認証
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
type: kubernetes.io/basic-auth
stringData:
  username: admin
  password: the-password
```

### 5. `kubernetes.io/ssh-auth` — SSH 秘密鍵
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ssh-key
type: kubernetes.io/ssh-auth
stringData:
  ssh-privatekey: |
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAAOCBKM... (秘密鍵の内容)
    -----END PRIVATE KEY-----
```

### 6. `kubernetes.io/tls` — TLS 証明書と秘密鍵
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
type: kubernetes.io/tls
stringData:
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDXTCCAkWgAwIBAgIJA... (証明書の内容)
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAAOCBKM... (秘密鍵の内容)
    -----END PRIVATE KEY-----
```

### 7. `bootstrap.kubernetes.io/token` — Bootstrap token
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-sample
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  token-id: 32qqsd
  token-secret: mq6f0l38as09lv5m
```

---

## Sealed Secrets を使った安全な Secret 管理（推奨）

**重要**: このリポジトリでは平文の Secret を **Git にコミットしてはいけません**。必ず SealedSecret として暗号化してください。

### ❌ するべきではないこと
```yaml
# これは絶対にコミットしてはいけません！
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
data:
  password: dXNlcmFkbWluMTIz  # base64 はエンコーディング（暗号化ではない）
```

### ✅ 推奨される方法: SealedSecret

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
  namespace: default
spec:
  encryptedData:
    username: AgBxk7J3LPj9ZL2k4xJ...  # 暗号化されたデータ
    password: AgBkL9mQ2kx8nH3pYx...   # 暗号化されたデータ
  template:
    metadata:
      name: my-secret
      namespace: default
    type: Opaque
    stringData:
      username: ""
      password: ""
```

このファイルを Git にコミットできます。クラスタ内の `sealed-secrets` controller が SealedSecret を検出すると、自動で復号化して Secret リソースを作成します。

---

## Sealed Secrets のセットアップと使い方

詳細なセットアップ手順は `argocd/sealed-secrets/install.md` を参照してください。

### クイックスタート

1. **sealed-secrets をクラスタにインストール（Argo CD 経由）**
   ```bash
   kubectl apply -f argocd/applications/sealed-secrets.yaml
   ```

2. **ローカルに `kubeseal` CLI をインストール**
   ```bash
   brew install kubeseal  # macOS
   # または Linux: wget + tar
   ```

3. **生の Secret を SealedSecret に暗号化**
   ```bash
   # 生の Secret YAML を作成
   cat > my-secret.yaml << 'EOF'
   apiVersion: v1
   kind: Secret
   metadata:
     name: my-secret
     namespace: default
   type: Opaque
   stringData:
     username: admin
     password: my-secure-password
   EOF
   
   # SealedSecret に暗号化
   kubeseal -f my-secret.yaml -w my-sealed-secret.yaml
   
   # 生の Secret を削除
   rm my-secret.yaml
   
   # Git にコミット
   git add my-sealed-secret.yaml
   git commit -m "Add sealed secret"
   ```

4. **Argo CD で同期**
   ```bash
   kubectl apply -f my-sealed-secret.yaml
   # または Argo CD が自動で同期
   
   # 確認
   kubectl get sealedsecrets
   kubectl get secrets
   ```

---

## 暗号化キーの管理

sealed-secrets のキーペアはクラスタ内に保存されます。キーを復号化するには `sealed-secrets` controller が必要です。

**キーのバックアップ（重要）**

```bash
# 秘密鍵をバックアップ
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml
git add sealed-secrets-key.backup.yaml
git commit -m "Backup sealed-secrets key"
```

**キーの復元**

```bash
kubectl apply -f sealed-secrets-key.backup.yaml
```

---

## Pre-commit チェック

このリポジトリでは `secretlint` を使ってコミット前に平文シークレットをチェックしています。

```bash
npm run check:secrets
```

以下の場合は検出されます:
- API キー、トークン（`api_key=`, `token=` など）
- SSH 秘密鍵、パスワード
- AWS/GCP/Azure クレデンシャル

---

## トラブルシューティング

**Q: 既存の Secret を SealedSecret に変換したい**

```bash
# クラスタから Secret を取得
kubectl get secret my-secret -o yaml > my-secret.yaml

# 生のデータを stringData に変換
# （注意: 平文データを扱うため、ローカルのセキュアな環境で実行）
kubeseal -f my-secret.yaml -w my-sealed-secret.yaml

# 生の Secret を削除し、SealedSecret をコミット
rm my-secret.yaml
git add my-sealed-secret.yaml
git commit -m "Convert to sealed secret"
```

**Q: 異なるクラスタで使用する SealedSecret**

各クラスタが異なる encryption キーを持つため、一つのクラスタで暗号化した SealedSecret は別クラスタでは復号化できません。複数クラスタ運用の場合は、各クラスタ用に SealedSecret を作成してください。

```bash
# 別クラスタ向け
kubeseal -f my-secret.yaml -w my-sealed-secret-cluster2.yaml \
  --kubeconfig ~/.kube/config-cluster2
```

**Q: SealedSecret が Secret に復号化されない**

1. sealed-secrets controller が running か確認:
   ```bash
   kubectl get pods -n kube-system | grep sealed-secrets
   ```

2. SealedSecret の namespace と Secret template の namespace が一致しているか確認。

3. キーペアが最新か確認:
   ```bash
   kubectl get secret -n kube-system sealed-secrets-key
   ```

---

## 参考

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [公式ドキュメント](https://sealed-secrets.dev/)
- このリポジトリの `argocd/sealed-secrets/install.md`
