#!/bin/bash
# Run this after updating usr_config.h and/or user_modules.h. Creates patch files.
MYDIR="$(pwd)"
CONF="./nodemcu-firmware/app/include"
if [[ -f $CONF/user_modules.h.original ]]; then
  diff $CONF/user_modules.h.original $CONF/user_modules.h >$MYDIR/user_modules.h.patch
  echo "user_modules.h.patch updated"
fi
if [[ -f $CONF/user_config.h.original ]]; then
  diff $CONF/user_config.h.original $CONF/user_config.h >$MYDIR/user_config.h.patch
  echo "user_config.h.patch updated"
fi
