#!/bin/bash
set -e

# Sealed Secret 作成スクリプト
# 使用方法: ./create-sealed-secret.sh <secret-name> <namespace> <env-file>
# 例: ./create-sealed-secret.sh misskey-secrets misskey misskey-secrets.env

SECRET_NAME="${1:?Secret name required (e.g., misskey-secrets)}"
NAMESPACE="${2:?Namespace required (e.g., misskey)}"
ENV_FILE="${3:?Env file required (e.g., misskey-secrets.env)}"

CERT_PATH="${HOME}/my-sealed-secrets-public-key.crt"

# === プロジェクトルートの確認 ===
if [ ! -d "argocd-apps" ]; then
  echo "❌ Error: argocd-apps directory not found"
  echo "Please run this script from the project root directory"
  echo "Current directory: $(pwd)"
  exit 1
fi

# === ステップ 1: 公開鍵を取得（初回または更新） ===
echo "🔑 Fetching K3s sealed-secrets public key from k3s-1..."

# 一時ファイル
TEMP_CERT="/tmp/sealed-secrets-temp.crt"

# 方法1: リモートサーバーから sealed-secrets-* シークレットを取得
if ssh k3s-1 'SECRET_NAME=$(sudo kubectl get secret -n kube-system -o name | grep sealed-secrets | head -1 | cut -d/ -f2) && [ -n "$SECRET_NAME" ] && sudo kubectl get secret "$SECRET_NAME" -n kube-system -o jsonpath="{.data.tls\.crt}" 2>/dev/null | base64 -d' | cat > "$TEMP_CERT" 2>/dev/null && \
   [ -s "$TEMP_CERT" ]; then
  cp "$TEMP_CERT" "$CERT_PATH"
  echo "✅ Public key fetched and saved to $CERT_PATH"

# 方法2: ローカルの kubectl（kubeconfig がある場合）
elif SECRET_NAME=$(kubectl get secret -n kube-system -o name 2>/dev/null | grep sealed-secrets | head -1 | cut -d/ -f2) && \
   [ -n "$SECRET_NAME" ] && \
   kubectl get secret "$SECRET_NAME" -n kube-system -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$TEMP_CERT" 2>/dev/null && \
   [ -s "$TEMP_CERT" ]; then
  cp "$TEMP_CERT" "$CERT_PATH"
  echo "✅ Public key fetched locally and saved to $CERT_PATH"

# 方法3: 既存の公開鍵を使用
elif [ -f "$CERT_PATH" ] && [ -s "$CERT_PATH" ]; then
  echo "✅ Using existing public key at $CERT_PATH"

# エラー
else
  echo "❌ Error: Could not fetch or find sealed-secrets public key"
  echo ""
  echo "🔍 Debugging steps (run on k3s-server-1):"
  echo "   1. Check if sealed-secrets is installed:"
  echo "      sudo kubectl get pods -n kube-system | grep sealed"
  echo "      sudo kubectl get pods -n sealed-secrets 2>/dev/null | grep sealed"
  echo ""
  echo "   2. Check available secrets:"
  echo "      sudo kubectl get secret -n kube-system"
  echo "      sudo kubectl get secret -n sealed-secrets 2>/dev/null"
  echo ""
  echo "   3. If found, get the certificate manually:"
  echo "      sudo kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/sealing-key.crt"
  echo ""
  echo "📝 Then copy to local machine:"
  echo "   scp k3s-1:~/sealing-key.crt ~/my-sealed-secrets-public-key.crt"
  exit 1
fi

rm -f "$TEMP_CERT"

# === ステップ 2: Env ファイルをチェック ===
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Error: $ENV_FILE not found"
  exit 1
fi

# === ステップ 3: Sealed Secret を作成 ===
SEALED_FILE="argocd-apps/secrets/${SECRET_NAME}.enc.yaml"

# ディレクトリがなければ作成
mkdir -p argocd-apps/secrets

echo "📦 Creating sealed secret from $ENV_FILE..."
echo "   Secret Name: $SECRET_NAME"
echo "   Namespace: $NAMESPACE"

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-env-file="$ENV_FILE" \
  --dry-run=client -o yaml | \
  kubeseal --cert "$CERT_PATH" -o yaml \
  > "$SEALED_FILE"

echo "✅ Sealed secret created: $SEALED_FILE"
echo ""
echo "📝 Next steps:"
echo "   1. Review the sealed secret: cat $SEALED_FILE"
echo "   2. Commit and push:"
echo "      git add $SEALED_FILE"
echo "      git commit -m \"chore: add $SECRET_NAME sealed secret\""
echo "      git push"
echo ""
echo "💡 After pushing, ArgoCD will automatically apply the sealed secret to the cluster"
