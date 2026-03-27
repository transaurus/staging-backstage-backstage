#!/usr/bin/env bash
set -euo pipefail

# prepare.sh for backstage/backstage
# Docusaurus ^3.9.0, Yarn 4.8.1 (Berry/Corepack), Node 22+
# Docusaurus path: microsite/
# Clones repo, installs deps, applies content fixes.
# Does NOT run write-translations or build.

REPO_URL="https://github.com/backstage/backstage"
BRANCH="master"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== prepare.sh: backstage/backstage ==="

# --- Node version: require Node 22+ ---
NODE_22_PATH="/opt/hostedtoolcache/node/22.22.1/x64/bin"
if [ -d "$NODE_22_PATH" ]; then
    export PATH="$NODE_22_PATH:$PATH"
fi

NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo "0")
echo "Current Node version: $(node --version 2>/dev/null || echo 'not found')"
if [ "$NODE_MAJOR" -lt "22" ]; then
    echo "Trying to find Node 22 in hostedtoolcache..."
    HOSTED_NODE=$(ls /opt/hostedtoolcache/node/ 2>/dev/null | grep '^22\.' | tail -1)
    if [ -n "$HOSTED_NODE" ]; then
        export PATH="/opt/hostedtoolcache/node/$HOSTED_NODE/x64/bin:$PATH"
    fi
    NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo "0")
    if [ "$NODE_MAJOR" -lt "22" ]; then
        echo "ERROR: Need Node 22+ but have $(node --version 2>/dev/null || echo 'not found')."
        exit 1
    fi
fi
echo "Node version: $(node --version)"
echo "npm version: $(npm --version)"

# --- Corepack + Yarn 4.8.1 ---
echo "Enabling corepack..."
corepack enable || npm install -g corepack
corepack prepare yarn@4.8.1 --activate
echo "Yarn version: $(yarn --version)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning $REPO_URL (depth 1, branch $BRANCH)..."
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
    echo "Clone complete."
else
    echo "source-repo/ already exists, skipping clone."
fi

cd "$REPO_DIR"

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes from fixes.json..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            } else if (op.type === 'replace') {
                console.log('  skip (find not found):', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

# --- Install dependencies in microsite ---
echo "Installing dependencies in microsite/..."
cd microsite
yarn install --immutable

echo "[DONE] Repository is ready for docusaurus commands."
