#!/bin/sh
# Rebuild the offline renderer from pinned npm packages in a disposable directory.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mermaid_temp=$(mktemp -d)
trap 'rm -rf "$mermaid_temp"' EXIT
npm install --prefix "$mermaid_temp" --ignore-scripts mermaid@12.1.0 esbuild@0.28.2
printf '%s\n' "import mermaid from 'mermaid'; window.mermaid = mermaid;" > "$mermaid_temp/entry.js"
"$mermaid_temp/node_modules/.bin/esbuild" "$mermaid_temp/entry.js" --bundle --minify --format=iife --target=safari17 --outfile="$project_dir/App/Resources/mermaid.js"
