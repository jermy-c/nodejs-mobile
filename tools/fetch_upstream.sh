#!/bin/bash
set -e

clone_dir=".cache/node"
mobile_root_dir="$(pwd)"
last_build_file="last_mobile_build.yml" 

# --- Step 1: Extract old Node.js version from last_mobile_build.yml ---
if [ ! -f "$last_build_file" ]; then
  echo "Error: $last_build_file does not exist in current directory."
  exit 1
fi

old_tag=$(grep '^nodejs_version:' "$last_build_file" | awk '{print $2}')

if [ -z "$old_tag" ]; then
  echo "Error: Could not find nodejs_version in $last_build_file."
  exit 1
fi

echo "Old Node.js version from $last_build_file: $old_tag"

# --- Step 2: Ask for base version and clone Node.js if needed ---
read -p "Enter base version of node (e.g. v22): " base_version

if [ ! -d "$clone_dir" ]; then
  echo "Cloning Node.js repository into $clone_dir..."
  git clone https://github.com/nodejs/node.git "$clone_dir"
fi

cd "$clone_dir"
git fetch --tags

# Verify the old_tag exists in the node repo
if ! git rev-parse --verify "$old_tag" >/dev/null 2>&1; then
  echo "Error: tag $old_tag does not exist in Node.js repository."
  exit 1
fi

# --- Step 3: Prompt for newer version tag ---
echo "Available tags for base version $base_version:"
new_tags=$(git tag -l "$base_version.*" | sort -V)
select new_tag in $new_tags; do
  if [ -n "$new_tag" ]; then
    break
  else
    echo "Invalid selection."
  fi
done

echo "Selected newer tag: $new_tag"

# --- Step 4: Checkout newer tag and create squash commit branch ---
git checkout "$new_tag"

if git rev-parse --verify nodejs-mobile-update >/dev/null 2>&1; then
  git branch -D nodejs-mobile-update
fi

git checkout -b nodejs-mobile-update

git reset --soft "$old_tag"

git commit -m "Update Node.js to $new_tag"

# --- Step 5: Generate patch in .cache/ ---
git format-patch -1 HEAD -o ../

patch_file=$(ls ../*.patch | tail -n 1)
echo "Patch file created: $patch_file"

# --- Step 6: Return to mobile repo root ---
cd "$mobile_root_dir"

# --- Step 7: Apply patch with partial commit and conflict handling ---

echo "Applying patch $patch_file..."

if git am --3way --ignore-space-change --reject "$patch_file"; then
  echo "Patch applied cleanly with no conflicts."
else
  echo "Patch applied with some conflicts. Conflicted files contain conflict markers and .rej files."

  if git diff --cached --quiet; then
    echo "No staged changes to commit for clean files."
  else
    git commit --no-verify -m "Partial patch applied: clean files committed."
    echo "Committed cleanly applied changes."
  fi

  conflicted_files=$(git diff --name-only --diff-filter=U)

  if [ -z "$conflicted_files" ]; then
    echo "No conflicted files detected after patch application."
  else
    git add $conflicted_files
    git commit --no-verify -m "Partial patch applied: files with conflicts unmerged for manual resolution."
    echo "Committed conflicted files with conflicts left to resolve manually:"
    echo "$conflicted_files"
  fi

  echo "Please manually resolve the conflicts and continue your workflow."
fi

# --- Step 8: Update last_build.yml with new nodejs_version ---
if [ -f "$last_build_file" ]; then
  sed "s/^nodejs_version:.*/nodejs_version: $new_tag/" "$last_build_file"
  echo "Updated $last_build_file with nodejs_version: $new_tag"
else
  echo "Warning: $last_build_file not found; skipping update."
fi

echo "=== Script completed ==="
