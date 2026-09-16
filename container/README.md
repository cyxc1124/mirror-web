# Container deployment

The root multi-stage Dockerfile compiles the complete Jekyll/Vite website while building the image. The final `web` target starts from the official `nginx:1.30.5-trixie` image and adds the compiled files at `/srv/site` and the fancyindex module. It serves HTTP on port 8080 as UID/GID 10001. Ruby, Node.js, source, and build dependencies remain in intermediate build stages.

The [official NGINX image](https://github.com/nginx/docker-nginx/tree/master/stable/debian) supplies NGINX, njs, and envsubst. A separate `nginx-modules` stage compiles fancyindex 0.5.2 against the same NGINX version, using source archives verified by SHA-256. Only the resulting module is copied into the runtime image; no NGINX package installation or compiler is needed in the final stage. Keep both NGINX base tags, the NGINX source URL, and its checksum aligned when upgrading.

CI publishes this NGINX image with the website included as `ghcr.io/cyxc1124/mirror-web`. That is the image Helm pulls: the GHCR name identifies this site's packaged NGINX image, while `nginx:1.30.5-trixie` is its official base.

## Build-time website configuration

The build merges these Jekyll files in order, with later values taking precedence:

1. `_config.yml`: base website configuration.
2. `container/site.yml`: reusable defaults for the private container deployment.
3. `container/site-production.yml`: production website overrides, selected by the `SITE_CONFIG` build argument.

The production profile sets the public URL to `https://mirrors.cyxc.club:7443` and the internal URL to `https://mirrors.cyxc.club`. Change this file for website metadata such as the title, brand, or hostname. Changes to configuration, templates, or frontend assets require a new image build and deployment.

Build the runtime image after initializing submodules:

```sh
git submodule update --init
docker build --build-arg SITE_CONFIG=container/site-production.yml \
  -t ghcr.io/cyxc1124/mirror-web:cyxc-v0.2.0 .
```

The Dockerfile defaults to the production profile. Another checked-in profile can be selected with `--build-arg SITE_CONFIG=container/site-other.yml`; use `--build-arg SITE_CONFIG=` to build only the reusable defaults. Paths are relative to the repository and must be included in the Docker build context. Do not put credentials in website configuration or build arguments.

## Runtime and Helm

The workspace's independent web Helm chart starts only the NGINX runtime container. There is no build init container, build ConfigMap, or shared site output volume. The chart rejects the removed `site` and `builder` values.

Set `manager.url` to the manager Service and `persistence.existingClaim` to the PVC owned by the worker release. Mirror files are mounted read-only at `/data/mirrors`. The image's `/srv/site` is used directly. The runtime requires writable `/tmp`; the chart supplies an emptyDir while keeping the root filesystem read-only.

Outside Helm, set `TUNASYNC_MANAGER_URL` to an HTTP(S) origin such as `http://manager:14242`. Startup only renders the NGINX configuration from that environment variable and starts NGINX. It does not compile pages or install dependencies.

When migrating an existing web release, move any old `site` overrides into the build profile, publish the new image, and set its tag in the production values. Upgrade with `--reset-values -f web/values-production.yaml` and include all required runtime overrides in that file, so obsolete saved Helm values are discarded.

NGINX emits relative directory redirects so clients retain their public HTTPS origin and port behind Traefik or router DNAT. Set the site's public URL, including any external port, in the build profile. The container continues to listen on HTTP 8080.

Routes:

- `/healthz`: NGINX health check.
- `/static/tunasync.json`: read-only proxy to the manager's `/jobs` endpoint; synchronization status remains live.
- `/`: built website, with mirror files and fancy directory indexes as the fallback.
- `/legacy_index`: server-rendered mirror list through njs.

The private site uses a compact shared footer without upstream organizational branding. At the user's request, the footer links to the original Web and Tunasync repositories and their cyxc1124 forks. The container defaults exclude upstream news and disable site-specific monitoring and download lists. Help pages start disabled; enable only pages appropriate to your mirror and supply accurate site configuration and download data. Never populate this deployment with the upstream mirror's live status JSON.

## CI publishing

Fork releases use the independent `cyxc-vMAJOR.MINOR.PATCH` Git tag namespace, starting with `cyxc-v0.2.0`. Keep upstream tags unchanged and never move or reuse a published fork tag.

`.github/workflows/docker-images.yml` builds the `web` target for linux/amd64 and linux/arm64 using the production profile. Pull requests build without publishing. Pushes to master and `cyxc-v*` tags, plus manual workflow runs, publish to GHCR using GITHUB_TOKEN. Release images preserve the complete Git tag, for example `ghcr.io/cyxc1124/mirror-web:cyxc-v0.2.0`. Master builds also publish `latest` and `sha-<short SHA>` for development.

After a fork-tag image build succeeds, the workflow creates its GitHub Release. The web chart package is attached to that release. Its current chart version is `0.2.0`, appVersion and image.tag are `cyxc-v0.2.0`, and its image pull policy is `IfNotPresent`.

Builder stages are no longer published as separate images. `Dockerfile.build` remains the original standalone build-environment option; the deployment workflow and Helm charts use the new Dockerfile's final runtime image.
