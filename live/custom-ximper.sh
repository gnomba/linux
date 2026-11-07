#!/bin/bash

set -e

# https://browser-use.com/tools/random-user-agent
WGET_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"
WGET_CMD="wget -q -c --show-progress --user-agent=\"${WGET_USER_AGENT}\""

# Исходный список пакетов через пробел
PACKAGES="curl kpartx wget xorriso unzip syslinux syslinux-data squashfs-tools cdrkit-utils genisoimage"


vWORKDIR="${PWD}/ximper_custom"
vIMGFILE="${vWORKDIR}/live"
vROOTFSDIR="${vWORKDIR}/../squashfs-root"
mkdir -pv "${vWORKDIR}"
vBASEURL="https://download.etersoft.ru/pub/Etersoft/XimperLinux/Current/ISO"
vISOFILE="$(curl -s ${vBASEURL}/ | grep -oP '(?<=href=")[^"]*' | grep -v "\.\." | head -n 1)"
vMD5FILE="${vISOFILE}.md5"
vISOINFO="${vISOFILE}.info"

${WGET_CMD} "${vBASEURL}/${vISOFILE}"
${WGET_CMD} "${vBASEURL}/${vMD5FILE}"

md5sum --check "${vMD5FILE}" || { echo "MD5 checksum verification failed!"; exit 1; }

xorriso -indev "${vISOFILE}" -toc -pvd_info > "${vISOINFO}"
xorriso -osirrox on -indev ${vISOFILE} -extract / ${vWORKDIR}

sudo unsquashfs ${vIMGFILE}
rm -fv ${vIMGFILE}

sudo mount -v --bind /dev ${vROOTFSDIR}/dev
sudo mount -v --bind /sys ${vROOTFSDIR}/sys
sudo mount -v --bind /proc ${vROOTFSDIR}/proc
sudo mount -v --bind /dev/pts ${vROOTFSDIR}/dev/pts

echo -e "nameserver 77.88.8.1\nnameserver 77.88.8.8\nnameserver 8.8.4.4" | sudo tee ${vROOTFSDIR}/etc/resolv.conf
#sudo chroot ${vROOTFSDIR} apt-get update
sudo chroot ${vROOTFSDIR} epm -y full-upgrade
sudo chroot ${vROOTFSDIR} epmi -y distrobox podman kontainer konsole
#echo -e "container_always_pull=\"0\"\ncontainer_manager=\"podman\"" | sudo tee ${vROOTFSDIR}/home/<username???>/.distroboxrc
#echo "<username???>:524288:65536" | tee -a ${vROOTFSDIR}/etc/subuid ${vROOTFSDIR}/etc/subgid
#echo "StartupWMClass=org.kde.kontainer" | sudo tee -a {vROOTFSDIR}/usr/share/applications/io.github.DenysMb.Kontainer.desktop
#sudo chroot ${vROOTFSDIR} chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap
#sudo chroot ${vROOTFSDIR} chmod a+x /usr/bin/newuidmap /usr/bin/newgidmap
#sudo chroot ${vROOTFSDIR} control newuidmap public
#sudo chroot ${vROOTFSDIR} control newgidmap public
#sudo chroot ${vROOTFSDIR} podman system migrate
sudo chroot ${vROOTFSDIR} epm -y autoremove
sudo chroot ${vROOTFSDIR} epm autoorphans
sudo chroot ${vROOTFSDIR} remove-old-kernels

sudo umount -v ${vROOTFSDIR}/dev/pts
sudo umount -v ${vROOTFSDIR}/proc
sudo umount -v ${vROOTFSDIR}/sys
sudo umount -lfv ${vROOTFSDIR}/dev

sudo mksquashfs ${vROOTFSDIR}/ ${vIMGFILE}
sudo rm -rf ${vROOTFSDIR}

vVOLUMEID="$(grep 'Volume Id    : ' ${vISOINFO} | sed 's/^Volume Id    : //')"; echo "vVOLUMEID=${vVOLUMEID}"
xorriso \
  -indev "${vISOFILE}" \
  -outdev "${vISOFILE//.iso/_custom.iso}" \
  -volid "${vVOLUMEID}" \
  -boot_image any replay \
  -compliance joliet_long_names \
  -map ${vWORKDIR} /

sudo rm -rf ${vWORKDIR} ${vISOINFO}

diff -u <(xorriso -indev ${vISOFILE} -toc -pvd_info) <(xorriso -indev ${vISOFILE//.iso/_custom.iso} -toc -pvd_info)

exit 0
