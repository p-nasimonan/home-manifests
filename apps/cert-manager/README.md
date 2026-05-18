ClusterIssuer and Cloudflare DNS01

This folder contains cert-manager Helm chart values and helper manifests.

To enable ACME DNS-01 via Cloudflare you must create a sealed secret in the
`cert-manager` namespace containing your Cloudflare API token. Create a file
named `cloudflare-creds.env` with the following content:

```
api-token=YOUR_CLOUDFLARE_API_TOKEN
```

Then run (from repository root):

```
./create-sealed-secret.sh harbor-cloudflare-token cert-manager cloudflare-creds.env
```

This will produce a sealed secret YAML in `apps/cert-manager/` (named
`harbor-cloudflare-token.enc.yaml`). Rename the secret to `cloudflare-api-token`
or adjust `clusterissuer-letsencrypt-prod.yaml` accordingly.

After that, ArgoCD will sync the `cert-manager` Application and the
`ClusterIssuer` will be able to request certificates via Cloudflare DNS-01.
