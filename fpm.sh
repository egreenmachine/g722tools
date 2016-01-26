#!/usr/bin/env bash
set -euo pipefail # http://redsymbol.net/articles/unofficial-bash-strict-mode/

# Define RPM variables
#
# Note that the Release number cannot be relied upon for version comparisons,
# as is the case with our node module RPMs.
#
# fpm 1.4.0 uses the first line of the Description for the Summary
# This has since changed:
# https://github.com/jordansissel/fpm/commit/275d2f4702b5674fed6912672a6509e59573284e

NAME="sip-g722tools"
VERSION=$(cat VERSION | cut -d = -f 2)
RELEASE="0.$(git rev-parse --short=7 HEAD).jnctn.el6"
URL="https://tools-handler.jnctn.net/git/?p=${NAME}.git;a=summary"
SUMMARY="g722 encoder and decoder"
DESCRIPTION=$"$SUMMARY\n\n(RPM built by fpm.sh in the SRPM)"
LICENSE="GPL"

# stash all changes, so git commit accurately reflects build
git status | grep "working directory clean" || git stash save --all "stashed by fpm.sh, token=$RANDOM"

# install build tools
command -v gem &>/dev/null || yum install rubygems
yum list installed rpm-build &>/dev/null || yum install rpm-build
yum list installed ruby-devel &>/dev/null || yum install ruby-devel # https://github.com/jordansissel/fpm#system-packages
yum list installed gcc &>/dev/null || yum install gcc # https://github.com/jordansissel/fpm#system-packages
yum list installed automake &>/dev/null || yum install automake
command -v fpm &>/dev/null || gem install fpm # https://github.com/jordansissel/fpm#get-with-the-download

# fpm 1.4.0 doesn't play nicely with cabin 0.8.0, so install 0.7.2 instead.
# Dylan noticed this on media-relay4-0.55b. We talked about it (privately):
# https://onsip.slack.com/archives/D0993HJNR/p1450973174000002
# and found a workaround on GitHub:
# https://github.com/jordansissel/fpm/issues/1051#issuecomment-165890735
if gem list cabin | grep 0.8.; then
    >&2 echo "Removing above cabin gems and installing 0.7.2 instead. You may want to undo this later."
    gem uninstall --all --executables cabin
    gem install cabin -v 0.7.2
fi

FPM="fpm"
FPM="$FPM -s dir"
FPM="$FPM -t rpm"
FPM="$FPM --version $VERSION"
FPM="$FPM --iteration $RELEASE"
FPM="$FPM --name $NAME"
FPM="$FPM --url $URL"
FPM="$FPM --license $LICENSE"
# suppress fpm warning about missing epoch field
# https://github.com/jordansissel/fpm/issues/381#issuecomment-166976521
FPM="$FPM --log error"

echo "Building src.rpm"

# build SRPM
$FPM \
  --prefix /usr/local/src/$NAME \
  --description "$DESCRIPTION" \
  $(git ls-files) > /dev/null

# rename SRPM
mv "$NAME-$VERSION-$RELEASE.x86_64.rpm" "$NAME-$VERSION-$RELEASE.src.rpm"

echo "Building rpm"

# Do repo specific build instructions
TMP_BUILD=`pwd`/build
mkdir -p $TMP_BUILD
./bootstrap.sh
./configure --prefix=$TMP_BUILD
make
make install

# Note that if after-upgrade is not specified, then the RPM generated treats an
# upgrade as a remove and an install. It will not recognize upgrading as a
# separate case. The RPM upgrade will run the after-install script and then it
# will run the after-upgrade script.
PREFIX=/usr
# The files to put in the non-src RPM
FILES="bin share"
# build RPM
$FPM \
    -C $TMP_BUILD \
  --prefix $PREFIX \
  --description "$DESCRIPTION" \
  $FILES

make clean && make distclean
rm -r $TMP_BUILD
echo "To remove untracked files (build files, etc.), run:"
echo "    git clean -df"
