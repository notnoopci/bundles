#!/bin/sh

set -eu

ACTION=${1:-generate}

MANIFEST_SOURCE="${MANIFEST_SOURCE:-https://raw.githubusercontent.com/docker-library/official-images/master/library/${BASE_REPO}}"
IMAGE_CUSTOMIZATIONS=${IMAGE_CUSTOMIZATIONS:-}

NEW_ORG=${NEW_ORG:-circleci}
BASE_REPO_BASE=$(echo $BASE_REPO | cut -d/ -f2)
NEW_REPO=${NEW_REPO:-${NEW_ORG}/${BASE_REPO_BASE}}

function find_tags() {
  curl -sSL "$MANIFEST_SOURCE" \
    | grep Tags \
    | sed  's/Tags: //g' \
    | sed 's|, | |g' \
    |grep -v -e '-'
}

SHARED_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TEMPLATE=${TEMPLATE:-basic}
VARIANTS=${VARIANTS:-none}

function find_template() {
  # find the right template - start with invoker path
  # then check this path
  template=$1

  if [ -e "$(dirname pwd)/Dockerfile-${template}.template" ]
  then
    echo "$(dirname pwd)/Dockerfile-${template}.template"
    exit 0
  fi

  if [ -e "${SHARED_DIR}/Dockerfile-${template}.template" ]
  then
    echo "${SHARED_DIR}/Dockerfile-${template}.template" 
    exit 0
  fi

  exit 1
}

function render_template() {
  TEMP=$(mktemp)
  printf "%s\n" "${IMAGE_CUSTOMIZATIONS}" > $TEMP

  TEMPLATE_PATH=$(find_template $1)

  cat $TEMPLATE_PATH | \
    sed "s|{{BASE_IMAGE}}|$BASE_IMAGE|g" | \
    sed "/# BEGIN IMAGE CUSTOMIZATIONS/ r $TEMP"

  rm $TEMP
}


for tag in $(find_tags)
do
  echo $tag

  rm -rf $tag
  mkdir -p $tag

  BASE_IMAGE=${BASE_REPO}:${tag}
  NEW_IMAGE=${NEW_REPO}:${tag}

  render_template $TEMPLATE > $tag/Dockerfile

  case $ACTION in
  "build")
    pushd $tag
    docker build -t $NEW_IMAGE .
    popd
    ;;
    "publish")
    pushd $tag
    docker build -t $NEW_IMAGE .
    docker push $NEW_IMAGE
    popd
    ;;
  esac

  # variants based on the basic image
  if [ ${VARIANTS} != "none" ]
  then
    for variant in ${VARIANTS}
    do

      echo "  $variant"
      BASE_IMAGE=${NEW_REPO}:${tag}
      NEW_IMAGE=${NEW_REPO}:${tag}-${variant}

      mkdir -p $tag/$variant
      render_template $variant > $tag/$variant/Dockerfile

      case $ACTION in
      "build")
        pushd $tag/$variant
        docker build -t $NEW_IMAGE .
        popd
        ;;
      "publish")
        pushd $tag/$variant
        docker build -t $NEW_IMAGE .
        docker push $NEW_IMAGE
	popd
        ;;
      esac
    done
  fi
done
