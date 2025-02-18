#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/depot/cli"
TOOL_NAME="depot"
TOOL_TEST="depot --help"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if depot is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
  list_github_tags
}

download_release() {
  local version filename url
  version="$1"
  filename="$2"

  # TODO: Adapt the release URL convention for depot
  url="$GH_REPO/releases/download/v${version}/$(get_tarball_name "$version")"

  echo "* Downloading $TOOL_NAME release $version..."
  curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}

# Implementation taken from
# https://stackoverflow.com/a/4024263
verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

get_tarball_name() {
  local version="$1"
  local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local arch="$(uname -m)"

  if [[ "$os" == "darwin" ]]; then
    # depot/cli PR #150 changed the release naming convention
    # https://github.com/depot/cli/pull/150
    if verlt "$version" "2.21.2"; then
      os="macOS"
    fi
  fi

  if [[ "$arch" == "arm64" ]] || [[ "$arch" == "aarch64" ]]; then
    arch="arm64"
  elif [[ "$arch" == *"arm"* ]] || [[ "$arch" == *"aarch"* ]]; then
    arch="arm"
  elif [[ "$arch" == *"386"* ]]; then
    arch="386"
  else
    arch="amd64"
  fi

  echo "${TOOL_NAME}_${version}_${os}_${arch}.tar.gz"
}
