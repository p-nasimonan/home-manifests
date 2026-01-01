# Cloudflare Tunnel セットアップ手順
---

## ステップ 1: Cloudflare API Token の取得（ローカルマシン - Webブラウザ）

1. [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) にログイン
2. 「API トークンを作成」をクリック
3. 「Cloudflare Zero Trust」テンプレートを選択、または以下の権限を持つカスタムトークンを作成：
   - Account - Cloudflare Tunnel: Edit
   - Account - Account Settings: Read
4. トークンをコピーして保存

## ステップ 2: Account ID の取得（ローカルマシン - Webブラウザ）

1. Cloudflare Dashboard のホーム画面
2. 右側のサイドバーに「Account ID」が表示されている
3. コピーして保存

---

## ステップ 3: cloudflare-tunnel.yaml を編集（ローカルマシン）

### 3-1. K3s サーバーの公開鍵を取得（2つの方法）

Sealed Secrets で暗号化するには、K3s サーバーの公開鍵が必要です。

#### 方法1: SSH でサーバーに接続して取得（推奨・簡単）

```bash
# ローカルマシンから K3s サーバーに SSH 接続
ssh root@192.168.0.9  # K3s サーバーの IP アドレス

# サーバー上で実行
kubectl get secrets -n kube-system

# 名前見つけてから
kubectl get secret sealed-secrets-xxxx -n kube-system -o jsonpath='{.data.tls\.crt}' | base64 -d > mycert.pem

# 出力をコピー（-----BEGIN CERTIFICATE----- から -----END CERTIFICATE----- まで）
```

ローカルマシンで以下のように保存：

```bash
# ローカルマシンで実行
cat > ~/my-sealed-secrets-public-key.crt << 'EOF'
# サーバーから取得した公開鍵をペースト
-----BEGIN CERTIFICATE-----
...ここに公開鍵の内容をペースト...
-----END CERTIFICATE-----
EOF
```

#### 方法2: kubectl で直接取得（kubeconfig 設定がある場合）

```bash
# ローカルマシンで実行
# 前提: ローカルマシンから K3s サーバーに kubectl でアクセスできる場合

kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/status=active -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > ~/my-sealed-secrets-public-key.crt
```

**⚠️ 前提条件：** ローカルマシンに `kubeconfig` が設定されていること

### 3-2. kubeseal コマンドをインストール（ローカルマシン）

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### 3-3. Cloudflare API Token を暗号化（ローカルマシン）

```bash
# ローカルマシンで実行

# Secret を作成（暗号化前）
kubectl create secret generic my-cf-creds \
  --from-literal=apiToken="あなたのAPIトークン" \
  --from-literal=accountId="あなたのアカウントID" \
   --from-literal=cloudflare-tunnel-name=home-kube \
  --dry-run=client -o yaml > apps/cloudflare-tunnel-ingress-controller/templates/raw-secret.yaml

# Sealed Secret に変換（K3s サーバーの公開鍵を使用）
kubeseal -f apps/cloudflare-tunnel-ingress-controller/templates/raw-secret.yaml -w apps/cloudflare-tunnel-ingress-controller/templates/secret.yaml --cert ~/my-sealed-secrets-public-key.crt --namespace cloudflare-tunnel-ingress-controller
```
