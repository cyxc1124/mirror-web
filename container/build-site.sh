#!/bin/sh
set -eu
output=${1:-/site}
work=$(mktemp -d)
scratch=$(mktemp -d)
trap 'rm -rf "$work" "$scratch"' EXIT HUP INT TERM
# Ruby rejects a world-writable emptyDir without the sticky bit as a temp dir.
# Keep ExecJS temporary files outside the ESM package directory as well.
export TMPDIR="$scratch"
cp -R /opt/mirror-web/. "$work/"
cd "$work"
# Vite writes configuration bundles beside the nearest node_modules directory.
# Keep that directory writable without copying the installed dependency tree.
mkdir -p node_modules
for dependency in /node_modules/* /node_modules/.bin; do
    ln -s "$dependency" "node_modules/${dependency##*/}"
done
# Runtime data comes from this deployment, never from the upstream mirror site.
mkdir -p static/status
mkdir -p .jekyll-cache
: > .jekyll-cache/vite-components.d.ts
printf '[]\n' > static/tunasync.json
printf '[]\n' > static/status/isoinfo.json
ruby -ryaml -e 'p="_data/options.yml"; d=YAML.load_file(p); d["unlisted_mirrors"]=[]; File.write(p, YAML.dump(d))'
config="_config.yml,container/site.yml"
if [ -n "${SITE_CONFIG:-}" ]; then
    test -r "$SITE_CONFIG"
    config="$config,$SITE_CONFIG"
fi
bundle exec jekyll build --config "$config" --destination "$output"
