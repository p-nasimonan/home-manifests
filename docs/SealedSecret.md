**⚠️ 前提条件：** 
- ローカルマシンに `kubeconfig` が設定されていること
- `~/.ssh/config` で `k3s-1` ホストが設定されていること（SSH で接続可能）

## セットアップ

### kubeseal をインストール

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

---

## 🚀 クイックスタート

```bash
# プロジェクトルートで実行

# 1. 環境変数ファイルを作成
# misskey
cat > misskey-secrets.env << 'EOF'
POSTGRES_PASSWORD=your-secure-postgres-password
POSTGRES_USER=misskey
POSTGRES_DB=misskey
DATABASE_URL=postgres://misskey:your-secure-postgres-password@misskey-postgresql-primary:5432/misskey
REDIS_PASSWORD=your-secure-redis-password
MISSKEY_SECRET_KEY=$(openssl rand -hex 32)
MISSKEY_SIGNING_KEY=$(openssl rand -hex 32)
MEILISEARCH_MASTER_KEY=$(openssl rand -hex 32)
EOF

# Cloudflare
cat > cloudflare-creds.env << 'EOF'
api-token=your-cloudflare-api-token
cloudflare-account-id=your-account-id
cloudflare-tunnel-name=home-kube
EOF

# 2. スクリプトで Sealed Secret を作成
# スクリプトが自動的に k3s-1 から公開鍵を取得します
./create-sealed-secret.sh misskey-secrets misskey misskey-secrets.env

./create-sealed-secret.sh my-cf-creds cloudflare-tunnel-ingress-controller cloudflare-creds.env


# 3. Git にコミット
(gitignoreで*.envは除いている)

```

---

## スクリプトの使用方法

### 基本構文

```bash
./create-sealed-secret.sh <secret-name> <namespace> <env-file>
```

### パラメータ

- `<secret-name>`: Kubernetes Secret の名前（例: `misskey-secrets`）
- `<namespace>`: デプロイ先の namespace（例: `misskey`）
- `<env-file>`: 環境変数ファイルのパス（例: `misskey-secrets.env`）

### 使用例

```bash
# Misskey 用
./create-sealed-secret.sh misskey-secrets misskey misskey-secrets.env

# Cloudflare 用
./create-sealed-secret.sh my-cf-creds cloudflare-tunnel-ingress-controller cloudflare-creds.env

# Minecraft 用
./create-sealed-secret.sh minecraft-secrets minecraft minecraft-secrets.env
```

### スクリプトの動作

1. ✅ `k3s-1` から Sealed Secrets の公開鍵を自動取得（SCP）
2. ✅ env ファイルから Kubernetes Secret を作成
3. ✅ kubeseal で暗号化
4. ✅ `argocd-apps/secrets/` に保存
