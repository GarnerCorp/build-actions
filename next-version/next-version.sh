set -eu

if [ "$DEBUG" == 'true' ]; then
  set -x
fi

bump_version() {
    current_version=$1
    bump_type=$2
    IFS='.' read -r -a version_parts <<< "$current_version"
    major=${version_parts[0]}
    minor=${version_parts[1]}
    patch=${version_parts[2]}

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "::error ::Invalid bump type: $bump_type" >&2
            exit 1
            ;;
    esac

    new_version="$major.$minor.$patch"
    echo $new_version
}

generate_release_notes() {
    source=$1
    notes=$(mktemp)
    if [ -z "$source" ] || [ ! -d "$source" ]; then
        return
    fi
    for file in $(find $source -type f -mindepth 1 -maxdepth 1 ! -name '.*' || true); do
      (
        echo "### $(basename "$file")"
        cat "$file"
        echo
        echo
      ) >> "$notes"
      git rm -q -f "$file"
    done
    if [ -s "$notes" ]; then
        echo "$notes"
    fi
}

if [ ! -s $VERSION_FILE ]; then
    echo "::error :: could not find version file: $VERSION_FILE"
    exit 1
fi

major_notes=$(generate_release_notes "$MAJOR")
minor_notes=$(generate_release_notes "$MINOR")

if [ -n "$major_notes" ]; then
    bump_type="major"
elif [ -n "$minor_notes" ]; then
    bump_type="minor"
else
    bump_type="patch"
fi

current_version=$(perl -ne 'next unless s/.*$ENV{VERSION_PATTERN}/$1/; print' "$VERSION_FILE")

new_version=$(bump_version "$current_version" "$bump_type")

commit_log=$(mktemp)
(
    echo "commit-log=$commit_log"
    echo "version=$new_version"
    echo "old-version=$current_version"
) >> "$GITHUB_OUTPUT"

create_section() {
    section=$1
    file=$2
    if [ -n "$file" ] && [ -s "$file" ]; then
        echo "## $section changes"
        echo
        cat "$file"
    fi
}

echo "Proposing $bump_type version bump from $current_version to $new_version"
(
    (
        create_section major "$major_notes"
        create_section minor "$minor_notes"
    ) | tee "$commit_log"
)
