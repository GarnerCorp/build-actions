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

docker context create multiarch 2> /dev/null || true


if [ "$(uname)" = "Linux" ]; then
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
fi

echo ::group::Use buildx-multiarch
docker buildx use buildx-multiarch ||
  docker buildx create --driver docker-container --use multiarch --name buildx-multiarch
echo ::end"group"::

if [ -n "$PLATFORMS" ]; then
  PLATFORM_ARGS="--platform $PLATFORMS"
fi

if [ -n "$BUILD_ARGS" ]; then
  BUILD_ARGS="$(echo $BUILD_ARGS | tr ',' ' ' | xargs -n 1 echo --build-arg)"
fi

echo $BUILD_ARGS | xargs docker buildx build $PLATFORM_ARGS $BUILD_CONTEXT -t $PUSH_CONTEXT -f $BUILD_DIRECTORY/$DOCKERFILE --push

echo "image=$PUSH_CONTEXT" >> $GITHUB_OUTPUT
