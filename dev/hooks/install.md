# Git hooks

Git hooks automatically execute some code before or after some git actions.

Installing git hooks is not required but can make the development experience easier by running some checks in advance that can prevent CI failure.

## Installation

Run the following command on the root of this repo:

```sh
for f in ./dev/hooks/*; do
  if [ -x "$f" ]; then
    echo "Linking hook $f"
    ln --symbolic --force "../../$f" "./.git/hooks/${f##*/}"
  fi
done
```

This command overwrites any existing hooks in the local git directory, use with caution.

## Remove

Run the following command on the root of this repo:

```sh
for f in ./.git/hooks/*; do
  if [ -L "$f" ]; then
    resolved_symlink=$(realpath "$f")
    if [[ "$resolved_symlink" =~ .*/dev/hooks/[^/]*$ ]]; then
      echo "Removing hook $f"
      rm "$f" 
    fi
  fi
done
```