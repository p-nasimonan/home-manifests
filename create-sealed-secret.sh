#!/bin/bash
set -e

# Sealed Secret 作成スクリプト
# 使用方法:
#   ./create-sealed-secret.sh --name <secret-name> --namespace <ns> <env-file>
#   ./create-sealed-secret.sh -n <secret-name> -ns <ns> <env-file>
#   ./create-sealed-secret.sh <secret-name> <namespace> <env-file>  # 位置引数（後方互換性）
#   ./create-sealed-secret.sh --name <name> --namespace <ns> --from-file <key=path>  # ファイルベース
#   ./create-sealed-secret.sh --name <name> --namespaces <ns1,ns2,ns3> --from-file <key=path> --output-dir <dir>  # 複数 namespace
#
# 例:
#   ./create-sealed-secret.sh --name misskey-secrets --namespace misskey misskey-secrets.env
#   ./create-sealed-secret.sh -n minecraft-secrets -ns minecraft minecraft-secrets.env
#   ./create-sealed-secret.sh --name proxmox-csi-config --namespace kube-system \
#     --from-file config.yaml=proxmox-csi-config.yaml
#   ./create-sealed-secret.sh --name volsync-rclone-config \
#     --namespaces misskey,vrc-queue-monitor,n8n \
#     --from-file rclone.conf=volsync-minio.env \
#     --output-dir apps/volsync-backup

# デフォルト値
SECRET_NAME=""
NAMESPACE=""
NAMESPACES=()
ENV_FILE=""
FILE_ARGS=()
FROM_FILE_MODE=false
OUTPUT_DIR=""

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
    --namespaces)
      IFS=',' read -ra NAMESPACES <<< "$2"
      shift 2
      ;;
    --output-dir|-o)
      OUTPUT_DIR="$2"
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

# --namespace と --namespaces を統合
if [ -n "$NAMESPACE" ]; then
  NAMESPACES=("$NAMESPACE" "${NAMESPACES[@]}")
fi

# 必須引数チェック
if [ -z "$SECRET_NAME" ]; then
  echo "❌ Error: Secret name is required"
  echo "Usage: ./create-sealed-secret.sh --name <secret-name> --namespace <namespace> <env-file>"
  exit 1
fi

if [ ${#NAMESPACES[@]} -eq 0 ]; then
  echo "❌ Error: --namespace or --namespaces is required"
  exit 1
fi

if [ "$FROM_FILE_MODE" = false ] && [ -z "$ENV_FILE" ]; then
  echo "❌ Error: Env file or --from-file is required"
  exit 1
fi

CERT_PATH="${HOME}/my-sealed-secrets-public-key.crt"

# === ステップ 1: 公開鍵を取得（初回または更新） ===
echo "🔑 Fetching K3s sealed-secrets public key from k3s-1..."

TEMP_CERT="/tmp/sealed-secrets-temp.crt"

if ssh k3s-1 'SECRET_NAME=$(sudo kubectl get secret -n kube-system -o name | grep sealed-secrets | head -1 | cut -d/ -f2) && [ -n "$SECRET_NAME" ] && sudo kubectl get secret "$SECRET_NAME" -n kube-system -o jsonpath="{.data.tls\.crt}" 2>/dev/null | base64 -d' > "$TEMP_CERT" 2>/dev/null && \
   [ -s "$TEMP_CERT" ]; then
  cp "$TEMP_CERT" "$CERT_PATH"
  echo "✅ Public key fetched and saved to $CERT_PATH"

elif [ -f "$CERT_PATH" ] && [ -s "$CERT_PATH" ]; then
  echo "✅ Using existing public key at $CERT_PATH"

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

# === ステップ 3: namespace ごとに Sealed Secret を作成 ===
MULTI=${#NAMESPACES[@]}

for NS in "${NAMESPACES[@]}"; do
  # 出力ファイル名: 複数 namespace のときは <name>-<ns>.enc.yaml
  if [ "$MULTI" -gt 1 ]; then
    SEALED_FILE="${SECRET_NAME}-${NS}.enc.yaml"
  else
    SEALED_FILE="${SECRET_NAME}.enc.yaml"
  fi

  # --output-dir が指定されていれば移動先のパスに
  if [ -n "$OUTPUT_DIR" ]; then
    SEALED_FILE="${OUTPUT_DIR}/${SEALED_FILE}"
  fi

  echo "📦 Creating sealed secret..."
  echo "   Secret Name: $SECRET_NAME"
  echo "   Namespace:   $NS"
  echo "   Output:      $SEALED_FILE"

  if [ "$FROM_FILE_MODE" = true ]; then
    FROM_FILE_OPTS=()
    for file_arg in "${FILE_ARGS[@]}"; do
      FROM_FILE_OPTS+=("--from-file=$file_arg")
    done

    kubectl create secret generic "$SECRET_NAME" \
      --namespace "$NS" \
      "${FROM_FILE_OPTS[@]}" \
      --dry-run=client -o yaml | \
      kubeseal --cert "$CERT_PATH" -o yaml \
      > "$SEALED_FILE"
  else
    kubectl create secret generic "$SECRET_NAME" \
      --namespace "$NS" \
      --from-env-file="$ENV_FILE" \
      --dry-run=client -o yaml | \
      kubeseal --cert "$CERT_PATH" -o yaml \
      > "$SEALED_FILE"
  fi

  echo "✅ Sealed secret created: $SEALED_FILE"
  echo ""
done

echo "💡 After pushing, ArgoCD will automatically apply the sealed secret to the cluster"
