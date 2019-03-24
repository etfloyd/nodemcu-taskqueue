#!/bin/bash
# Updates nodemcu firmware from the dev branch and builds using docker image
# Firmware folder is assumed to be in folder containing this script
# See run_once.sh.
#
MYDIR="$(pwd)"
cd nodemcu-firmware
git checkout dev
git pull
git checkout timerfix
git merge dev
git merge pr2497
docker pull marcelstoer/nodemcu-build
docker run --rm -ti -v `pwd`:/opt/nodemcu-firmware marcelstoer/nodemcu-build build
cd $MYDIR
