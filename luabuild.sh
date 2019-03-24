#!/bin/bash
#set -x

# Set to device flash size
export FLASH_SIZE="1MB"

# Set to lfs size specified in user_config.h:
export LFS_SIZE="0x28000"

# These exports are generated based on currently loaded nodemcu firmware. To get these values:
# 1. Build nodemcu firmware using dockerbuild.sh
# 2. Flash firmware to ESP-8266 or ESP-8285 using flashit.sh
# 3. Connect via uart with tty terminal (ESplorer will work for this)
# 4. Run lfs_exports.lua from ESP-82xx console, copy and paste the export lines here:
export LFS_MAPPED="0x402b0000"
export LFS_BASE="0xb0000"
# 5. Don't forget to update whenever you flash a new firmware build.

## This section is not needed in current setup, kept as reference example.
## Compile and flash files into spiffs
#luac.cross -o _init.lc _init.lua && \
#rm -f spiffs.img spiffs.ofs && \
#spiffsimg -f 'spiffs.img' -S $FLASH_SIZE -U $(cat firmware.size) -o spiffs.ofs -r spiffs.cmd && \
#esptool.py --port /dev/ttyUSB0 --baud 460800 --chip esp8266 write_flash --flash_mode dout $(cat spiffs.ofs) spiffs.img
#rm -f spiffs.img spiffs.offs *.lc

# compile and flash lfs
luac.cross -a "$LFS_MAPPED" -f -m $LFS_SIZE -o lfs.img src/*.lua && \
esptool.py --port /dev/ttyUSB0 --baud 460800 --chip esp8266 write_flash --flash_mode dout $LFS_BASE lfs.img
rm -f lfs.img
