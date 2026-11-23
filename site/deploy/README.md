# Deploying freeroom.hblabs.co

- `deployment.yaml`, `ingress.yaml`: Deployment, Service and Ingress in the `cloud` namespace of the
  livekit cluster.
- Images: `ghcr.io/hblabs-co/freeroom-site:<version>`, public, built and pushed by
  `.github/workflows/site.yml` with GitHub's own token. No registry or cluster credential is stored
  in GitHub.

## Releasing a new version

```sh
echo 0.1.4 > site/VERSION && git commit -am "site 0.1.4: ..." && git push
git tag site/v0.1.4 && git push origin site/v0.1.4     # the workflow builds and pushes the image
```

The cluster then updates itself: an updater inside the cluster watches GHCR for new semver tags
and rolls the Deployment to the new version (pull model; the cluster API is never reached from
outside). Until that updater is installed, roll out by hand:

```sh
kubectl --context livekit -n cloud set image deploy/service-freeroom service-freeroom=ghcr.io/hblabs-co/freeroom-site:0.1.4
```
