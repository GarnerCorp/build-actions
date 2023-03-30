#!/bin/sh -e

exit_unless_git_dirty() {
  if git diff HEAD --quiet; then
    echo "::warning ::There were no git changes (are you rerunning workflow?), exiting..."
    exit 0
  fi
}

if [ -z "$BRANCH" ] || [ -z "$HEAD_SHA" ]; then
  echo "::error ::Usage $0. Please ensure "'`$BRANCH` and `$HEAD_SHA` are set.'
  exit 1
fi

if [ "$BRANCH" != "$DEFAULT_BRANCH" ] && [ -z "$PR_NUMBER" ]; then
  exit 0
fi

if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  echo -n "$HEAD_SHA" > "$DEFAULT_BRANCH".txt
  git add "$DEFAULT_BRANCH".txt
  exit_unless_git_dirty
  commitInfo="Trigger $DEFAULT_BRANCH e2e test"
else
  echo -n "$HEAD_SHA" > "$PR_NUMBER".txt
  git add "$PR_NUMBER".txt
  exit_unless_git_dirty
  commitInfo="Trigger e2e test for pull request $PR_NUMBER"
fi

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_MAIL"

if [ -n "$PROJECT_PRETTY" ]; then
  prefix="[$PROJECT_PRETTY] "
fi
if [ -n "$PR_REPO_URL" ]; then
  COMMIT_URL="$PR_REPO_URL/commit/$HEAD_SHA"
fi
git commit -m "$prefix$commitInfo

$COMMIT_URL
"

git push origin HEAD ||
  git pull --rebase origin HEAD && git push origin HEAD
