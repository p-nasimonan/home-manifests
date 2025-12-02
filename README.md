# home-manifests

このリポジトリは自宅クラスタ向けの Kubernetes マニフェスト群です。
Argo CD を使った GitOps 管理のための最小スケルトンを `argocd/` に含めています。

使い方の概略は `argocd/install-argocd.md` を参照してください。

コミット前チェック (Lefthook + secretlint)
------------------------------------------

このリポジトリでは Node ベースの Git フック管理ツール `lefthook` でコミット前にシークレットをチェックします。

セットアップ手順:

```bash
# 依存をインストール (lefthook と secretlint)
npm install

# Git フックを有効化
npx lefthook install

# 以後のコミットで自動的に secretlint が実行されます
```

手動でシークレットをチェックする場合:

```bash
npm run check:secrets
```


