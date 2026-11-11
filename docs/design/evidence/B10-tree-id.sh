#!/usr/bin/env bash
# B10: cost of a "tree id" (the hash of the working tree's content, honouring .gitignore, including untracked files).
# The measured repo is never written to: the index is a temp file and new objects go to a temp object directory.
# Usage: B10-tree-id.sh <repo> [exclude-pathspec ...]
set -u
repo=$(cd "${1:?repo}" && pwd); shift
ms() { local s=$EPOCHREALTIME; "$@" >/dev/null 2>&1; local e=$EPOCHREALTIME; echo $(( (${e/./} - ${s/./}) / 1000 )); }
gitdir=$(git -C "$repo" rev-parse --absolute-git-dir); objs=$(git -C "$repo" rev-parse --git-path objects); case $objs in /*) ;; *) objs="$repo/$objs";; esac
ex=(); for p in "$@"; do ex+=(":(exclude)$p"); done

tree_id() {   # $1 = cold (index rebuilt from HEAD, every file re-hashed) | warm (the repo's index copied, so unchanged files are not re-read)
  local tmp; tmp=$(mktemp -d); mkdir -p "$tmp/objects"
  export GIT_INDEX_FILE="$tmp/index" GIT_OBJECT_DIRECTORY="$tmp/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$objs"
  if [ "$1" = warm ] && [ -f "$gitdir/index" ]; then cp "$gitdir/index" "$tmp/index"; else git -C "$repo" read-tree HEAD 2>/dev/null || git -C "$repo" read-tree --empty; fi
  git -C "$repo" add -A -- . "${ex[@]}" 2>/dev/null
  git -C "$repo" write-tree
  unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES; rm -rf "$tmp"
}

before=$(find "$gitdir" -type f -newer "$gitdir/HEAD" 2>/dev/null | wc -l); stamp=$(mktemp); sleep 1
echo "repo: $repo"
echo "tracked files: $(git -C "$repo" ls-files | wc -l)   working tree size: $(du -sh --exclude=.git "$repo" 2>/dev/null | cut -f1)"
echo "git ls-files:            $(ms git -C "$repo" ls-files) ms"
echo "git status --porcelain:  n/a (it may refresh the repo's index, so it is not run on a read-only repo)"
a=$(tree_id cold); echo "tree id, cold index:     $(ms tree_id cold) ms   -> $a"
b=$(tree_id warm); echo "tree id, warm index:     $(ms tree_id warm) ms   -> $b"
[ "$a" = "$b" ] && echo "cold and warm agree: yes" || echo "cold and warm agree: NO"
echo "HEAD tree:               $(git -C "$repo" rev-parse 'HEAD^{tree}' 2>/dev/null)  (differs from the tree id when the working tree is dirty or has untracked files)"
echo "files in the repo's git dir changed by this script: $(find "$gitdir" -type f -newer "$stamp" 2>/dev/null | wc -l)"
rm -f "$stamp"
