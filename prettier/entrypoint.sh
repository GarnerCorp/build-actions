#!/bin/bash
# e is for exiting the script automatically if a command fails, u is for exiting if a variable is not set
# x would be for showing the commands before they are executed
set -eu
shopt -s globstar

if [ "$INPUT_DEBUG" == 'true' ]; then
  set -x
fi

$GITHUB_ACTION_PATH/../scripts/add-matchers.sh

# FUNCTIONS
# Function for setting up git env in the docker container (copied from https://github.com/stefanzweifel/git-auto-commit-action/blob/master/entrypoint.sh)
_git_setup ( ) {
  cat <<- EOF > $HOME/.netrc
    machine github.com
    login $GITHUB_ACTOR
    password $INPUT_GITHUB_TOKEN
    machine api.github.com
    login $GITHUB_ACTOR
    password $INPUT_GITHUB_TOKEN
EOF
  chmod 600 $HOME/.netrc

  git config --global user.email "$(perl -e 'my $user=$ENV{GITHUB_ACTOR}; $user =~ s/\W+/-/g; print $user')@users.noreply.github.com"
  git config --global user.name "$GITHUB_ACTOR"
}

# Checks if any files are changed
_git_changed() {
  git status -s --untracked-files=no | grep -q .
}

_git_changes() {
  git diff
}

_has_upstream() {
  git remote get-url --push origin | grep -q ..
}

_dry_run() {
  [ "$INPUT_DRY" == 'true' ]
}

_only_changed() {
  [ "$INPUT_ONLY_CHANGED" == 'true' ]
}

_amend_commit() {
  [ "$INPUT_SAME_COMMIT" == 'true' ]
}

summarize_changes() {
  (
    (
      echo "## ${1:-Changes}"
      echo '```sh'
      git format-patch --stdout $GITHUB_SHA..HEAD | tee /dev/stderr
      echo '```'
    ) >> "$GITHUB_STEP_SUMMARY"
  ) 2>&1
}

echo "# [Prettier](https://prettier.io/)" >> "$GITHUB_STEP_SUMMARY"

(
# PROGRAM
# Changing to the directory
cd "$GITHUB_ACTION_PATH"

echo "Installing prettier..."

case $INPUT_WORKING_DIRECTORY in
  false)
    ;;
  *)
    cd $INPUT_WORKING_DIRECTORY
    ;;
esac

case $INPUT_PRETTIER_VERSION in
  false)
    npm install -g --silent prettier
    ;;
  *)
    npm install -g --silent prettier@$INPUT_PRETTIER_VERSION
    ;;
esac

# Install plugins
if [ -n "$INPUT_PRETTIER_PLUGINS" ]; then
  for plugin in $INPUT_PRETTIER_PLUGINS; do
    echo "Checking plugin: $plugin"
    # check regex against @prettier/xyz
    if ! echo "$plugin" | grep -Eq '(@prettier\/plugin-|(@[a-z\-]+\/)?prettier-plugin-){1}([a-z\-]+)'; then
      echo "$plugin does not seem to be a valid @prettier/plugin-x plugin. Exiting."
      exit 1
    fi
  done
  npm install -g --silent $INPUT_PRETTIER_PLUGINS
fi
)

check_paths=''
if echo "$INPUT_PRETTIER_OPTIONS" | grep -v -q /; then
  if [ -z "$INPUT_FILE_EXTENSIONS" ]; then
    if ! command -v jq >/dev/null; then
      apt-get update
      apt-get install jq
    fi
    INPUT_FILE_EXTENSIONS=$(
      prettier --support-info |
      jq -r '.languages[].extensions[]' |
      xargs
    )
  fi
  check_paths=$($GITHUB_ACTION_PATH/shell-glob-files.pl)
fi

git_blame_ignore_revs_log=$(mktemp)

log_blame_rev() {
  if [ "${INPUT_UPDATE_GIT_BLAME_IGNORE_REVS:-}" == 'true' ]; then
  (
    echo "# $1"
    git rev-parse --revs-only HEAD
  ) >> "$git_blame_ignore_revs_log"
  fi
}

if _git_changed && ! _amend_commit; then
  _git_setup
  git add -u
  git commit -n -m 'Record dirty files from before prettier'
  log_blame_rev 'Dirty commits from before prettier'
fi

logs_before=$(mktemp)
find ~/.npm/_logs -type f > "$logs_before"
logs_after=$(mktemp)
PRETTIER_RESULT=0
echo "Prettifying files..."
echo "Files:"
prettier_options="--no-error-on-unmatched-pattern $INPUT_PRETTIER_OPTIONS $check_paths"
prettier_out=$(mktemp)
prettier_err=$(mktemp)

dump_log() {
  file="$1"
  if [ -s "$file" ]; then
    title="${2:-$file}"
    (
      echo "### $title"
      echo '```sh'
      cat "$file"
      echo '```'
      echo
    ) >> "$GITHUB_STEP_SUMMARY"
    cat "$file"
  fi
}

prettier_output_summary() {
  (
    dump_log "$prettier_out" 'prettier.output'
    dump_log "$prettier_err" 'prettier.error'
  )
}

dry_run_check() {
  # case when --write is used with dry-run so if something is unpretty there will always have _git_changed
  if _dry_run; then
    summarize_changes 'Unpretty Files Changes'
    echo "Finishing dry-run. Exiting before committing." | tee -a "$GITHUB_STEP_SUMMARY"
    exit 1
  fi
}

npx prettier $prettier_options > "$prettier_out" 2> "$prettier_err" \
  || {
    PRETTIER_RESULT=$?;
    if [ "$PRETTIER_RESULT" -ne 1 ]; then
      prettier_output_summary
      find ~/.npm/_logs -type f > "$logs_after"
      (
        echo "# Problem running prettier with $prettier_options";
        echo '```'
        diff -U0 $logs_before $logs_after|perl -ne 'next unless s/^[+]([^+])/$1/; print' | xargs -n1 cat
        echo '```'
        exit 1;
      ) | tee -a "$GITHUB_STEP_SUMMARY"
    fi
  }

prettier_output_summary

# Ignore node modules and other action created files
if [ -d 'node_modules' ]; then
  rm -r node_modules/
  git checkout -- node_modules/ 2> /dev/null >/dev/null || true
fi

if [ -f 'package-lock.json' ]; then
  git checkout -- package-lock.json 2> /dev/null >/dev/null || true
fi

# To keep runtime good, just continue if something was changed
if ! _git_changed; then
  # case when --check is used so there will never be something to commit but there are unpretty files
  if [ "$PRETTIER_RESULT" -eq 1 ]; then
    echo "Prettier found unpretty files!" | tee -a "$GITHUB_STEP_SUMMARY"
    exit 1
  fi

  (
    if _dry_run; then
      echo "## dry-run complete"
    fi
    echo '## No unpretty files!'
  ) | tee -a "$GITHUB_STEP_SUMMARY"
  echo "Nothing to commit. Exiting."
  exit
fi

# Calling method to configure the git environment
_git_setup

if _only_changed; then
  # --diff-filter=d excludes deleted files
  OLDIFS="$IFS"
  IFS=$'\n'
  for file in $(git diff --name-only --diff-filter=d HEAD^..HEAD)
  do
    git add "$file"
  done
  IFS="$OLDIFS"
else
  # Add changes to git
  git add "${INPUT_FILE_PATTERN}" ||
    echo "Problem adding your files with pattern ${INPUT_FILE_PATTERN}" | tee -a "$GITHUB_STEP_SUMMARY"
fi

failed_push=""
# Commit and push changes back
if _amend_commit; then
  (
    echo "## Amending the current commit..."
    git pull
    git commit --amend --no-edit
  ) | tee -a "$GITHUB_STEP_SUMMARY"

  dry_run_check

  if _has_upstream; then
    git push origin -f || failed_push=1
  fi
else
  commit_canary=1
  if [ "$INPUT_COMMIT_DESCRIPTION" != "" ]; then
    git commit -n -m "$INPUT_COMMIT_MESSAGE" -m "$INPUT_COMMIT_DESCRIPTION" ${INPUT_COMMIT_OPTIONS:+"$INPUT_COMMIT_OPTIONS"} || commit_canary=
  else
    git commit -n -m "$INPUT_COMMIT_MESSAGE" ${INPUT_COMMIT_OPTIONS:+"$INPUT_COMMIT_OPTIONS"} || commit_canary=
  fi

  dry_run_check

  if [ -n "$commit_canary" ]; then
    log_blame_rev "Prettier"
  else
    echo "No files added to commit"
  fi
  if [ -s "$git_blame_ignore_revs_log" ]; then
    cat "$git_blame_ignore_revs_log" >> .git-blame-ignore-revs
    git add .git-blame-ignore-revs
    git commit -n -m 'Update .git-blame-ignore-revs'
  fi
  if _has_upstream; then
    git push origin ${INPUT_PUSH_OPTIONS:-HEAD} || failed_push=1
  fi
fi

if [ -n "$failed_push" ]; then
  summarize_changes
  exit 1
fi

echo "::notice title=Prettier::Changes pushed successfully."
(
  echo "## Changes pushed to remote..."
  echo '> [!IMPORTANT]'
  echo '> You should fetch the changes before making additional commits to the branch.'
) >> "$GITHUB_STEP_SUMMARY"

summarize_changes
