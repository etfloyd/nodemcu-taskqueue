#!/bin/bash
# Run this one time to do the initial setup:
#   clones nodemcu-firmware
#   creates timerfix branch from dev
#   merges pull request 2497 into timerfix branch
#   patches user_config.h and user_modules.h
# This can be rerun any time if you need to re-create or reset the environment
set -x
MYDIR="$(pwd)"
if [[ ! -d nodemcu-firmware ]]; then
  git clone --recurse-submodules https://github.com/nodemcu/nodemcu-firmware.git
  cd nodemcu-firmware
  git checkout dev
  git checkout -b timerfix
  git fetch origin pull/2497/head:pr2497
  git merge pr2497 -m "Merge pull request 2497 into timerfix branch"
else
  cd nodemcu-firmware
fi
CONF="./app/include"
if [[ ! -f $CONF/user_config.h.original ]]; then
  mv $CONF/user_config.h $CONF/user_config.h.original
fi
patch $CONF/user_config.h.original -i $MYDIR/user_config.h.patch -o $CONF/user_config.h
if [[ ! -f $CONF/user_modules.h.original ]]; then
  mv $CONF/user_modules.h $CONF/user_modules.h.original
fi
patch $CONF/user_modules.h.original -i $MYDIR/user_modules.h.patch -o $CONF/user_modules.h
git add --all
git commit -m "Updated user configs"
cd $MYDIR

echo "Sudo access required for installing and linking tools"

if ! [ -x "$(command -v esptool.py)" ]; then
  sudo pip install esptool
fi
# These symlink targets are created by dockerbuild.sh
if ! [ -L /usr/local/bin/luac.cross ]; then
  sudo ln -sf $MYDIR/nodemcu-firmware/luac.cross /usr/local/bin/luac.cross
fi
if ! [ -L /usr/local/bin/spiffsimg ]; then
  sudo ln -sf $MYDIR/nodemcu-firmware/tools/spiffsimg/spiffsimg /usr/local/bin/spiffsimg
fi
