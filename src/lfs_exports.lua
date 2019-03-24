-- Creates exports for luabuild.sh. Run this each time you flash new firmware
-- and copy the resulting exports to luabild.sh.
do
  local _,ma,fa=node.flashindex()
  for n,v in pairs{LFS_MAPPED=ma, LFS_BASE=fa} do
    print(('export %s="0x%x"'):format(n, v))
  end
end
