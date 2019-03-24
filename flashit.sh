#!/bin/bash
# Flash nodemcu firmware to /dev/ttyUSB0.
# Firmware folder is assumed to be at the same level as folder containing this script
# See 'dockerbuild.sh'
MYDIR="$(pwd)"
cd nodemcu-firmware
ESPBIN="$(ls -1atr ./bin/*.bin | tail -n1)"
echo "Flashing: $ESPBIN"
esptool.py --port /dev/ttyUSB0 --baud 460800 --chip esp8266 erase_flash
esptool.py --port /dev/ttyUSB0 --baud 460800 --chip esp8266 write_flash --flash_mode dout 0x0000 $ESPBIN
stat -c %s $ESPBIN >$MYDIR/firmware.size
cd $MYDIR
