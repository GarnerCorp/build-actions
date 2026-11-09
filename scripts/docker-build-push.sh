#!/usr/bin/env bash

set -e

$GITHUB_ACTION_PATH/../scripts/add-matchers.sh

BUILD_DIRECTORY="."
DOCKERFILE="Dockerfile"

usage() {
  echo "Usage: $0 -r repository -i image_name [-t tag] [-e rc] [-p platform1,platform2...] [-d build_directory] [-f dockerfile] [-c build_context] [-a build_args]"
  exit 1
}

while getopts r:i:t:d:f:p:e:c:a: opt; do
  case "$opt" in
  r)    REPOSITORY="$OPTARG";;
  i)    IMAGE="$OPTARG";;
  t)    TAG="$OPTARG";;
  d)    BUILD_DIRECTORY="$OPTARG";;
  f)    DOCKERFILE="$OPTARG";;
  p)    PLATFORMS="$OPTARG";;
  e)    RC="$OPTARG";;
  c)    BUILD_CONTEXT="$OPTARG";;
  a)    BUILD_ARGS="$OPTARG";;
  [?])  usage;;
  esac
done

for arg in REPOSITORY IMAGE; do
  if [ -z "${!arg}" ]; then
    usage
    exit 1
  fi
done

case "$GITHUB_REF_NAME" in
  master);;
  main);;
  "");;
  *) BRANCH="-$(echo "$GITHUB_REF_NAME" | tr / -)"
esac

PUSH_CONTEXT=${REPOSITORY}/${IMAGE}:${RC:-${TAG}${BRANCH}}
BUILD_IMAGE="$PUSH_CONTEXT"

if [ -n "${CRANE_REGISTRY:-}" ]; then
  BUILD_IMAGE="$CRANE_REGISTRY/${PUSH_CONTEXT#*/}"
fi

if [ -n "$PLATFORMS" ]; then
  PLATFORM_ARGS="--platform $PLATFORMS"
fi

if [[ "$PLATFORMS" == *,* ]] || [ -n "${CRANE_REGISTRY:-}" ]; then
  docker context create multiarch 2> /dev/null || true

  if [[ "$PLATFORMS" == *,* ]] && [ "$(uname)" = "Linux" ]; then
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  fi

  builder_name="buildx-multiarch"
  builder_options=()
  if [ -n "${CRANE_REGISTRY:-}" ]; then
    builder_name="buildx-multiarch-registry"
    builder_options+=(--driver-opt network=host)
  fi

  echo "::group::Use $builder_name"
  docker buildx use "$builder_name" ||
    docker buildx create --driver docker-container "${builder_options[@]}" --use multiarch --name "$builder_name"
  echo ::end"group"::
fi

if [ -n "$BUILD_ARGS" ]; then
  BUILD_ARGS="$(echo $BUILD_ARGS | tr ',' ' ' | xargs -n 1 echo --build-arg)"
fi

BUILD_SECRET_ARGS=()
while IFS= read -r build_secret; do
  if [ -n "$build_secret" ]; then
    BUILD_SECRET_ARGS+=(--secret "$build_secret")
  fi
done <<< "${BUILD_SECRETS:-}"

echo $BUILD_ARGS | xargs docker buildx build "${BUILD_SECRET_ARGS[@]}" $PLATFORM_ARGS $BUILD_CONTEXT -t "$BUILD_IMAGE" -f $BUILD_DIRECTORY/$DOCKERFILE --push
DIGEST=$(docker inspect --format='{{ index .RepoDigests 0 }}' "$BUILD_IMAGE" || true)

(
  echo "image=$PUSH_CONTEXT"
  echo "source=$BUILD_IMAGE"
  echo "digest=${DIGEST#*@}"
) >> $GITHUB_OUTPUT
