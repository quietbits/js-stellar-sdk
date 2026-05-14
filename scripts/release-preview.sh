#!/usr/bin/env bash
set -euo pipefail

# Practice run of the modernization preview release flow.
# Spec: .claude/notes/modernization-preview-release-spec.md
# Substitutions when porting to modernization:
#   'release-test'           → 'modernization'
#   '27.0.0-release-test'    → '27.0.0-modernization'
#   'quietbits/js-stellar-sdk' → 'stellar/js-stellar-sdk'

VERSION="${1:?Usage: $0 <version> (e.g. 27.0.0-release-test.1)}"
TAG="v${VERSION}"
TARBALL="stellar-stellar-sdk-${VERSION}.tgz"

if ! [[ "${VERSION}" =~ ^27\.0\.0-release-test\.[0-9]+$ ]]; then
  echo "Error: version must match 27.0.0-release-test.N (got: ${VERSION})" >&2
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "${CURRENT_BRANCH}" != "release-test" ]]; then
  echo "Error: must be on 'release-test' (currently on '${CURRENT_BRANCH}')" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: working tree must be clean before releasing" >&2
  exit 1
fi

gh auth status >/dev/null 2>&1 \
  || { echo "Error: 'gh auth login' required" >&2; exit 1; }
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "Error: tag ${TAG} already exists locally" >&2
  exit 1
fi
if gh release view "${TAG}" >/dev/null 2>&1; then
  echo "Error: GitHub release ${TAG} already exists" >&2
  exit 1
fi

cleanup() {
  rm -f "${TARBALL}"
  if [[ -n "${TREE_DIRTIED:-}" ]]; then
    git checkout -- .
  fi
}
trap cleanup EXIT

TREE_DIRTIED=1
pnpm version "${VERSION}" --no-git-tag-version --allow-same-version

npm pack --ignore-scripts

test -f lib/cjs/index.js
test -f lib/esm/index.js
test -f lib/esm/index.d.ts
test -f dist/stellar-sdk.js
test -f dist/stellar-sdk.min.js
test -f bin/stellar-js
test -f "${TARBALL}"

gh release create "${TAG}" \
  --target release-test \
  --prerelease \
  --title "${TAG} — release-test practice" \
  --notes "Practice run of the modernization preview release flow. Not a real release.

Install by adding to your \`package.json\`:
\`\`\`json
\"@stellar/stellar-sdk\": \"https://github.com/quietbits/js-stellar-sdk/releases/download/${TAG}/${TARBALL}\"
\`\`\`" \
  "${TARBALL}"

git checkout -- .
TREE_DIRTIED=

PREVIEW_FILE="PREVIEW.md"
NEW_CONTENT=$(cat <<EOF
Version: **${TAG}**

Add to your \`package.json\`:

\`\`\`json
"@stellar/stellar-sdk": "https://github.com/quietbits/js-stellar-sdk/releases/download/${TAG}/${TARBALL}"
\`\`\`
EOF
)
awk -v new_content="${NEW_CONTENT}" '
  /<!-- LATEST-PREVIEW:BEGIN -->/ { print; print new_content; in_block=1; next }
  /<!-- LATEST-PREVIEW:END -->/   { print; in_block=0; next }
  !in_block { print }
' "${PREVIEW_FILE}" > "${PREVIEW_FILE}.tmp" && mv "${PREVIEW_FILE}.tmp" "${PREVIEW_FILE}"

echo "Released ${TAG}"
echo "PREVIEW.md updated — please review and commit the change."
