前提: このリポジトリは Argo CD が既にクラスタ上に導入されていることを想定しています。

目的: Argo CD にリポジトリを登録し、このリポジトリ内の `argocd/applications/*.yaml` を使ってアプリを同期するための最小手順を示します。

1) リポジトリを Argo CD に登録（一例）

```bash
# argocd CLI 例
argocd login <argocd-server> --insecure
argocd repo add https://github.com/p-nasimonan/home-manifests

# または、Repository カスタムリソースを `argocd` 名前空間に apply して登録できます
```

2) Application の作成（このリポジトリ内の manifest を利用）

- もっとも直接的な方法: `kubectl apply` で `argocd` 名前空間に `Application` リソースを作成します（例）:

```bash
kubectl apply -f argocd/applications/example-app.yaml -n argocd
```

- 代替: `argocd` CLI や UI で手動作成することも可能です。

3) 同期の確認

```bash
argocd app get example-app
argocd app sync example-app
kubectl get deploy,svc -l app=example-app
```

補足: `kubectl apply` は "Application" リソースをクラスタに作るための代表的な手段ですが、必須ではありません。
- `kubectl apply` を使わずに済ませる方法:
	- Argo CD の UI / CLI から Application を作成する。 
	- 既存のブートストラップ repo（Argo CD が最初に監視する repo）に `argocd/applications/*.yaml` を置き、Argo CD がそのブートストラップを通じて子アプリを作成する（このブートストラップ自体は最初に一度だけ `kubectl apply` する必要がある場合が多い）。

要点まとめ:
- Argo CD が Application リソースを管理できれば、以後の同期は Argo CD が自動で行います。`kubectl apply` は Application をクラスタに作る（＝Argo CD に「このリソースを監視して同期してほしい」と指示する）ために使う一般的な方法ですが、UI/CLI/API で同等の操作が可能です。

