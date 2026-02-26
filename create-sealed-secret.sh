#!/bin/bash
set -e

# Sealed Secret 作成スクリプト
# 使用方法:
#   ./create-sealed-secret.sh --name <secret-name> --namespace <ns> <env-file>
#   ./create-sealed-secret.sh -n <secret-name> -ns <ns> <env-file>
#   ./create-sealed-secret.sh <secret-name> <namespace> <env-file>  # 位置引数（後方互換性）
#   ./create-sealed-secret.sh --name <name> --namespace <ns> --from-file <key=path>  # ファイルベース
# 
# 例:
#   ./create-sealed-secret.sh --name misskey-secrets --namespace misskey misskey-secrets.env
#   ./create-sealed-secret.sh -n minecraft-secrets -ns minecraft minecraft-secrets.env
#   ./create-sealed-secret.sh --name proxmox-csi-config --namespace kube-system \
#     --from-file config.yaml=proxmox-csi-config.yaml

# デフォルト値
SECRET_NAME=""
NAMESPACE=""
ENV_FILE=""
FILE_ARGS=()
FROM_FILE_MODE=false

# オプション引数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    --name|-n)
      SECRET_NAME="$2"
      shift 2
      ;;
    --namespace|--ns|-ns)
      NAMESPACE="$2"
      shift 2
      ;;
    --env|-e)
      ENV_FILE="$2"
      shift 2
      ;;
    --from-file|-f)
      FROM_FILE_MODE=true
      FILE_ARGS+=("$2")
      shift 2
      ;;
    -*)
      echo "❌ Unknown option: $1"
      exit 1
      ;;
    *)
      # 位置引数（後方互換性）
      if [ -z "$SECRET_NAME" ]; then
        SECRET_NAME="$1"
      elif [ -z "$NAMESPACE" ]; then
        NAMESPACE="$1"
      elif [ -z "$ENV_FILE" ]; then
        ENV_FILE="$1"
      fi
      shift
      ;;
  esac
done

# 必須引数チェック
if [ -z "$SECRET_NAME" ]; then
  echo "❌ Error: Secret name is required"
  echo "Usage: ./create-sealed-secret.sh --name <secret-name> --namespace <namespace> <env-file>"
  echo "       ./create-sealed-secret.sh -n <secret-name> -ns <namespace> <env-file>"
  echo "       ./create-sealed-secret.sh <secret-name> <namespace> <env-file>"
  echo "       ./create-sealed-secret.sh --name <name> --namespace <ns> --from-file <key=path>"
  exit 1
fi

if [ -z "$NAMESPACE" ]; then
  echo "❌ Error: Namespace is required"
  echo "Usage: ./create-sealed-secret.sh --name <secret-name> --namespace <namespace> <env-file>"
  exit 1
fi

if [ "$FROM_FILE_MODE" = false ] && [ -z "$ENV_FILE" ]; then
  echo "❌ Error: Env file or --from-file is required"
  echo "Usage: ./create-sealed-secret.sh --name <secret-name> --namespace <namespace> <env-file>"
  echo "       ./create-sealed-secret.sh --name <name> --namespace <ns> --from-file <key=path>"
  exit 1
fi

CERT_PATH="${HOME}/my-sealed-secrets-public-key.crt"

# === ステップ 1: 公開鍵を取得（初回または更新） ===
echo "🔑 Fetching K3s sealed-secrets public key from k3s-1..."

# 一時ファイル
TEMP_CERT="/tmp/sealed-secrets-temp.crt"

# 方法1: SSH経由でリモートサーバーから取得
if ssh k3s-1 'SECRET_NAME=$(sudo kubectl get secret -n kube-system -o name | grep sealed-secrets | head -1 | cut -d/ -f2) && [ -n "$SECRET_NAME" ] && sudo kubectl get secret "$SECRET_NAME" -n kube-system -o jsonpath="{.data.tls\.crt}" 2>/dev/null | base64 -d' > "$TEMP_CERT" 2>/dev/null && \
   [ -s "$TEMP_CERT" ]; then
  cp "$TEMP_CERT" "$CERT_PATH"
  echo "✅ Public key fetched and saved to $CERT_PATH"

# 方法2: 既存の公開鍵を使用（フォールバック）
elif [ -f "$CERT_PATH" ] && [ -s "$CERT_PATH" ]; then
  echo "✅ Using existing public key at $CERT_PATH"

# エラー
else
  echo "❌ Error: Could not fetch sealed-secrets public key via SSH"
  echo "Make sure:"
  echo "  1. SSH access to k3s-1 is working"
  echo "  2. Sealed Secrets is installed on K3s"
  echo "  3. You can run: ssh k3s-1 'sudo kubectl get secret -n kube-system | grep sealed'"
  exit 1
fi

rm -f "$TEMP_CERT"

# === ステップ 2: 入力ファイルをチェック ===
if [ "$FROM_FILE_MODE" = true ]; then
  for file_arg in "${FILE_ARGS[@]}"; do
    # key=path 形式または path 形式
    file_path="${file_arg#*=}"
    if [ ! -f "$file_path" ]; then
      echo "❌ Error: File not found: $file_path"
      exit 1
    fi
  done
else
  if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: $ENV_FILE not found"
    exit 1
  fi
fi

# === ステップ 3: Sealed Secret を作成 ===
SEALED_FILE="${SECRET_NAME}.enc.yaml"

echo "📦 Creating sealed secret..."
echo "   Secret Name: $SECRET_NAME"
echo "   Namespace: $NAMESPACE"

if [ "$FROM_FILE_MODE" = true ]; then
  # --from-file モード (YAML ファイルなど任意形式)
  FROM_FILE_OPTS=()
  for file_arg in "${FILE_ARGS[@]}"; do
    FROM_FILE_OPTS+=("--from-file=$file_arg")
  done
  echo "   Files: ${FILE_ARGS[*]}"

  kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    "${FROM_FILE_OPTS[@]}" \
    --dry-run=client -o yaml | \
    kubeseal --cert "$CERT_PATH" -o yaml \
    > "$SEALED_FILE"
else
  # --from-env-file モード (KEY=VALUE 形式)
  echo "   Env file: $ENV_FILE"

  kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-env-file="$ENV_FILE" \
    --dry-run=client -o yaml | \
    kubeseal --cert "$CERT_PATH" -o yaml \
    > "$SEALED_FILE"
fi

echo "✅ Sealed secret created: $SEALED_FILE"
echo ""
cat "$SEALED_FILE"
echo ""
echo "💡 After pushing, ArgoCD will automatically apply the sealed secret to the cluster"
