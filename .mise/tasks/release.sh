#!/usr/bin/env bash
#MISE description="Cut a release: mise run release <version> (e.g. mise run release 7.1.0)"
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: mise run release <version>  (e.g. mise run release 7.1.0)" >&2
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be X.Y.Z semver (got '$VERSION')" >&2
    exit 1
fi

TIDE_FISH="functions/tide.fish"
CHANGELOG="CHANGELOG.md"
TAG="v$VERSION"

# Confirm the version heading exists in the changelog
if ! grep -qF "## [$TAG][]" "$CHANGELOG"; then
    echo "Error: no entry for $TAG found in $CHANGELOG" >&2
    echo "Add a changelog entry before releasing." >&2
    exit 1
fi

# Date formatted like existing changelog entries: "Mar 14 2026"
TODAY=$(python3 -c "import datetime; d=datetime.date.today(); print(d.strftime('%b %-d %Y'))")

echo "Releasing $TAG on $TODAY"

# 1. Update version in tide.fish
sed -i.bak "s/echo 'tide, version [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'/echo 'tide, version $VERSION'/" "$TIDE_FISH"
rm -f "$TIDE_FISH.bak"

# 2. Stamp the date in CHANGELOG (replace (???) for this version's heading)
sed -i.bak "s|## \[$TAG\]\[\] (???)|## [$TAG][] ($TODAY)|" "$CHANGELOG"
rm -f "$CHANGELOG.bak"

# 3. Append reference link if not already present
REPO=$(git remote get-url origin | sed 's|.*github.com[:/]||; s|\.git$||')
LINK="[$TAG]: https://github.com/$REPO/tree/$TAG"
if ! grep -qF "$LINK" "$CHANGELOG"; then
    echo "$LINK" >> "$CHANGELOG"
fi

# 4. Commit and push
git add "$TIDE_FISH" "$CHANGELOG"
git commit -m "$TAG

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push

# 5. Extract release notes from CHANGELOG (content between first and second ## headings)
NOTES_FILE=$(mktemp)
awk 'found && /^## /{exit} /^## /{found=1; next} found' "$CHANGELOG" \
    | sed -E 's/\[(#[0-9]+)\]\[\]/\1/g' > "$NOTES_FILE"

gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

# 6. Force-update higher-level convenience tags (v7, v7.0)
MAJOR="v$(echo "$VERSION" | cut -d. -f1)"
MINOR="v$(echo "$VERSION" | cut -d. -f1-2)"
git tag -f "$MAJOR"
git tag -f "$MINOR"
git push origin "$MAJOR" "$MINOR" --force

echo "Done! $TAG released on GitHub (also updated $MAJOR and $MINOR)."
