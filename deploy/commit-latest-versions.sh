#!/bin/sh -e

$GITHUB_ACTION_PATH/../scripts/add-matchers.sh

exit_unless_git_dirty() {
  if git diff HEAD --quiet; then
    echo "::warning ::There were no git changes (are you rerunning workflow?), exiting..."
    exit 0
  fi
}

if [ -z "$BRANCH" ] || [ -z "$HEAD_SHA" ]; then
  echo "::error ::Usage $0. Please ensure "'`$BRANCH` and `$HEAD_SHA` are set.'
  if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    if [ -z "$BRANCH" ]; then
      missing=' $BRANCH'
      if [ -z "$HEAD_SHA" ]; then
        missing="s$missing and"
      fi
    fi
    if [ -z "$HEAD_SHA" ]; then
      missing="$missing"' $HEAD_SHA'
    fi
    echo ":x: Variable$missing must be set" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
fi

if [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "::notice ::Your run was to a non-default branch ($BRANCH != $DEFAULT_BRANCH), exiting..."
  exit 0
fi

(
  if [ -n "$SHA_FORMATTER" ]; then
    eval $SHA_FORMATTER
  else
    echo -n "$HEAD_SHA$SHA_SUFFIX"
  fi
) > "$VERSION_FILE"

git add "$VERSION_FILE"
exit_unless_git_dirty
commitInfo="Update $(basename $(pwd))"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_MAIL"

if [ -n "$PROJECT_PRETTY" ]; then
  prefix="[$PROJECT_PRETTY] "
fi
if [ -n "$REPO_URL" ]; then
  COMMIT_URL="$REPO_URL/commit/$HEAD_SHA"
fi
git commit -m "$prefix$commitInfo

$COMMIT_URL

$COMMIT_MESSAGE_SUFFIX
"

git push origin HEAD ||
  git pull --rebase origin HEAD && git push origin HEAD
