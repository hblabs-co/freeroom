# Deploying freeroom.hblabs.co

- `deployment.yaml`, `ingress.yaml`: Deployment, Service and Ingress in the `cloud` namespace of the
  livekit cluster.
- Image: `registry.4the.company/freeroom/site:<version>` (HB Labs registry, zot), pushed by
  `.github/workflows/site.yml` as the zot user `ci-freeroom`, which can only write to `freeroom/*`.
  Its API key is in this repository's secrets `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`.
- **Keel** in the cluster polls the registry every 2 minutes and rolls the Deployment to any newer
  patch or minor version (`keel.sh/policy: minor`). No cluster credential exists outside the cluster.

## Releasing a new version

```sh
echo 0.1.6 > site/VERSION && git commit -am "site 0.1.6: ..." && git push
git tag site/v0.1.6 && git push origin site/v0.1.6
```

The workflow builds and pushes the image (a few minutes); Keel deploys it within about 2 minutes
after that. A major version (1.0.0) is not rolled out automatically: change the image in
`deployment.yaml` and apply it.
