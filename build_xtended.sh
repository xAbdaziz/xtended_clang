#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

LOLZ_DIR="$(pwd)"

# Github info
git config --global user.name "xawlw"
git config --global user.email "abdulazizawlw@gmail.com"

# Inlined function to post a message
export BOT_MSG_URL="https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage"
function tg_post_msg() {
    curl -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHATID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=html" \
        -d text="$1"
}

# Build Info
lolz_date="$(date "+%Y%m%d")"              # ISO 8601 format
lolz_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
builder_commit="$(git rev-parse HEAD)"

# Send a notificaton to TG
tg_post_msg "<b>Xtended Clang Compilation Started</b>%0A<b>Date: </b><code>$lolz_friendly_date</code>%0A<b>CLANG Script Commit: </b><code>$builder_commit</code>%0A"

# Build LLVM
tg_post_msg "<code>Building LLVM...</code>"
./build-llvm.py \
	--clang-vendor "Xtended" \
	--targets "ARM;AArch64" \
	--shallow-clone \
	--pgo \
	--lto full \
	--m haswell \
    --build-stage1-only \
    --install-stage1-only

# Build binutils
tg_post_msg "<code>Building Binutils...</code>"
./build-binutils.py \
    --targets arm aarch64 \
    -m haswell

# Remove unused products
tg_post_msg "<code>Removing Unused Products...</code>"
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
tg_post_msg "<code>Stripping Remaining Products...</code>"
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    strip "${f::-1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
tg_post_msg "<code>Setting Library Load Paths for Portability...</code>"
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    # Remove last character from file output (':')
    bin="${bin::-1}"
    echo "$bin"
    patchelf --set-rpath "$LOLZ_DIR/install/lib" "$bin"
done

# Release Info
pushd llvm-project
llvm_commit="$(git rev-parse HEAD)"
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$llvm_commit"
popd
binutils_ver="2.34"
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

# Push to GitHub xawlw's clang builds repo
tg_post_msg "<code>Pushing New Xtended Clang Build to Github Repo...</code>"
git clone "https://xawlw:$GITHUB_TOKEN@github.com/Project-Xtended/prebuilts_clang_host_linux-x86_clang-xtended.git" --depth=1 my_repo
pushd my_repo
rm -fr ./*
cp -r ../install/* .
echo "$clang_version-Xtended_Clang-$lolz_date" >VERSION
git add .
git commit -m "Update to $lolz_date Build

LLVM commit: $llvm_commit_url
binutils version: $binutils_ver
Builder commit: https://github.com/xawlw/xtended_clang/commit/$builder_commit"
git push -f
lolzclang_commit="$(git rev-parse HEAD)"
lolzclang_commit_url="https://github.com/Project-Xtended/prebuilts_clang_host_linux-x86_clang-xtended/commit/$lolzclang_commit"
popd

tg_post_msg "<b>Xtended Clang Compilation Finished</b>%0A<b>Clang Version: </b><code>$clang_version</code>%0A<b>LLVM Commit: </b><code>$llvm_commit_url</code>%0A<b>Binutils Version: </b><code>$binutils_ver</code>%0A<b>Xtended Clang Commit: </b><code>$lolzclang_commit_url</code>"
