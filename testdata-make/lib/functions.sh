#!/bin/sh

require_command() {
    command_name=$1
    message=$2

    command -v "${command_name}" >/dev/null 2>&1 || {
        echo "ERROR: ${message}" >&2
        exit 1
    }
}

require_file() {
    file=$1
    message=$2

    if [ ! -s "${file}" ]; then
        echo "ERROR: ${message}" >&2
        echo "Missing file: ${file}" >&2
        exit 1
    fi
}

download_file() {
    url=$1
    target=$2
    partial="${target}.part"

    if [ -s "${target}" ]; then
        echo "Already present: ${target}"
        return 0
    fi

    mkdir -p "$(dirname -- "${target}")"

    if command -v wget >/dev/null 2>&1; then
        wget -c -O "${partial}" "${url}"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -C - -o "${partial}" "${url}"
    else
        echo "ERROR: wget or curl is required for downloads." >&2
        exit 1
    fi

    mv "${partial}" "${target}"
}
