#!/usr/bin/env bash

BUILD_DIRECTORY="."
DOCKERFILE="Dockerfile"

usage() {
  echo "Usage: $0 -r repository -i image_name [-t tag] [-e rc] [-p platform1,platform2...] [-d build_directory] [-f dockerfile] [-c build_context]"
  exit 1
}

while getopts r:i:t:d:f:p:e:c: opt; do
  case "$opt" in
  r)    REPOSITORY="$OPTARG";;
  i)    IMAGE="$OPTARG";;
  t)    TAG="$OPTARG";;
  d)    BUILD_DIRECTORY="$OPTARG";;
  f)    DOCKERFILE="$OPTARG";;
  p)    PLATFORMS="$OPTARG";;
  e)    RC="$OPTARG";;
  c)    BUILD_CONTEXT="$OPTARG";;
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

docker buildx use buildx-multiarch ||
  docker buildx create --driver docker-container --use multiarch --name buildx-multiarch

if [ -n "$PLATFORMS" ]; then
  PLATFORM_ARGS="--platform $PLATFORMS"
fi

docker buildx build $PLATFORM_ARGS $BUILD_CONTEXT -t $PUSH_CONTEXT -f $BUILD_DIRECTORY/$DOCKERFILE --push
