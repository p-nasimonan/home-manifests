Harbor secrets source

This directory keeps the Harbor secret source env file at `apps/harbor/harbor-secrets.env`.
Do not delete it after generating the SealedSecret; it is the editable source of truth for regenerating `harbor-secrets.enc.yaml`.

To regenerate:

```bash
./create-sealed-secret.sh --name harbor-secrets --namespace harbor --env apps/harbor/harbor-secrets.env --output-dir apps/harbor
```

The env file is ignored by git, so it can stay in the working tree without being committed.
