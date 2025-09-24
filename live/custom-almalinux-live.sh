#!/bin/bash

set -e

# === Выбор версии AlmaLinux ===
echo "Выберите версию Live ISO:"
echo "1) AlmaLinux 8 x86_64"
echo "2) AlmaLinux 9 x86_64"
echo "3) AlmaLinux 10 x86_64"
echo "4) AlmaLinux 10 x86_64_v2"
read -p "Введите номер версии [1-4]: " CHOICE

case $CHOICE in
  1) vVERSION=8; vARCH=x86_64; ISO_URL="https://repo.almalinux.org/almalinux/${vVERSION}/live/${vARCH}/AlmaLinux-${vVERSION}-latest-${vARCH}-Live-GNOME-Mini.iso" ;;
  2) vVERSION=9; vARCH=x86_64; ISO_URL="https://repo.almalinux.org/almalinux/${vVERSION}/live/${vARCH}/AlmaLinux-${vVERSION}-latest-${vARCH}-Live-GNOME-Mini.iso" ;;
  3) vVERSION=10; vARCH=x86_64; ISO_URL="https://repo.almalinux.org/almalinux/${vVERSION}/live/${vARCH}/AlmaLinux-${vVERSION}-latest-${vARCH}-Live-GNOME.iso" ;;
  4) vVERSION=10; vARCH=x86_64_v2; ISO_URL="https://repo.almalinux.org/almalinux/${vVERSION}/live/${vARCH}/AlmaLinux-${vVERSION}-latest-${vARCH}-Live-GNOME.iso" ;;
  *) echo "Неверный выбор"; exit 1 ;;
esac

# === Параметры ===
ISO_NAME="AlmaLinux-${vVERSION}-${vARCH}-live-original.iso"
ISO_INFO="${ISO_NAME//.iso/.txt}"
CUSTOM_ISO="AlmaLinux-${vVERSION}-${vARCH}-live-ssh.iso"
WORKDIR="$PWD/almalinux-live"
MOUNTDIR="$PWD/iso-mount"

PASSWORD="livepass"    # пароль для пользователя liveuser
ROOTPASS="rootpass"    # пароль для root
PUBKEY_FILE="$HOME/.ssh/id_rsa.pub"  # ваш публичный ключ

# === Подготовка ===
echo "[+] Создаём '$WORKDIR' ..."
mkdir -pv "$WORKDIR"

echo "[+] Скачиваем ISO..."
echo "    [+] $ISO_URL --> $ISO_NAME"
[ -f "$ISO_NAME" ] || curl --progress-bar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36" -L "$ISO_URL" -o "$ISO_NAME"

#echo "[+] Монтируем ISO..."
#echo "    [+] $ISO_NAME --> $MOUNTDIR"
#sudo mount -o loop "$ISO_NAME" "$MOUNTDIR"

#echo "[+] Копируем содержимое ISO..."
#echo "    [+] $MOUNTDIR/ --> $WORKDIR/)"
#sudo rsync -a "$MOUNTDIR/" "$WORKDIR/"

#echo "[+] Размонтируем ISO..."
#sudo umount -v "$MOUNTDIR"

echo "[+] Получение информации об образе..."
xorriso -indev $ISO_NAME -toc -pvd_info > $ISO_INFO
vVOLUMEID="$(grep 'Volume Id    : ' $ISO_INFO | sed 's/^Volume Id    : //')"; echo "vVOLUMEID=${vVOLUMEID}"
vBOOTCATALOG="$(awk -F"'" '/Boot catalog : / {print $2}' $ISO_INFO | sed 's/\///')"; echo "vBOOTCATALOG=${vBOOTCATALOG}"
vBOOTIMG="$(awk -F"'" '/boot_info_/ {print $2}' $ISO_INFO | sed 's/\///')"; echo "vBOOTIMG=${vBOOTIMG}"
vBOOTEFI="$(awk -F"'" '/platform_id=/ {print $2}' $ISO_INFO | sed 's/\///')"; echo "vBOOTEFI=${vBOOTEFI}"

echo "[+] Извлекаем содержимое ISO..."
echo "    [+] $ISO_NAME --> $WORKDIR"
xorriso -osirrox on -indev $ISO_NAME -extract / $WORKDIR

echo "[+] Переходим в $WORKDIR..."
cd "$WORKDIR"; pwd

echo "[+] Распаковываем squashfs..."
echo "    [+] Создаём папку squashfs..."
sudo mkdir -v squashfs
echo "    [+] Переходим в squashfs..."
cd squashfs; pwd
sudo unsquashfs ../LiveOS/squashfs.img
echo "    [+] Переходим в squashfs-root..."
cd squashfs-root; pwd

echo "[+] Версия AlmaLinux: ${vVERSION}..."
if [[ "${vVERSION}" == "8" || "${vVERSION}" == "9" ]]; then
    echo "    [+] Связываем файл LiveOS/rootfs.img с loop-устройством..."
    sudo losetup --find --partscan --show LiveOS/rootfs.img
    vLOOPDEV="$(sudo losetup -l | grep rootfs | awk '{print $1}')"
    echo "    [+] Loop-устройство: ${vLOOPDEV}..."
    vROOFSDIR="/mnt/rootfs"
    echo "    [+] Создаём vROOFSDIR: ${vROOFSDIR}..."
    sudo mkdir -pv ${vROOFSDIR}
    echo "    [+] Монтируем loop-устройство ${vLOOPDEV} в ${vROOFSDIR}..."
    sudo mount -v ${vLOOPDEV} ${vROOFSDIR}
else
    vROOFSDIR="."
    echo "    [+] vROOFSDIR: ${vROOFSDIR}..."
fi

# === НАЧАЛО кастомизации ===

echo "[+] Настраиваем sshd..."
echo "    [+] Включаем root, пароль и ключи..."
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo chmod +r ${vROOFSDIR}/etc/ssh/sshd_config

echo "[+] Добавляем systemd unit для SSH..."
cat <<LIVESSHSERVICE | sudo tee ${vROOFSDIR}/etc/systemd/system/live-ssh.service
[Unit]
Description=Enable SSH in Live session
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo 'liveuser:${PASSWORD}' | chpasswd"
ExecStart=/bin/bash -c "echo 'root:${ROOTPASS}' | chpasswd"
ExecStart=/bin/systemctl enable sshd
ExecStart=/bin/systemctl start sshd

[Install]
WantedBy=multi-user.target
LIVESSHSERVICE

sudo ln -s /etc/systemd/system/live-ssh.service ${vROOFSDIR}/etc/systemd/system/multi-user.target.wants/live-ssh.service

echo "[+] Добавляем ключи..."
if [ -f "$PUBKEY_FILE" ]; then
    echo "    [+] Копируем публичный ключ в ${vROOFSDIR}/etc/skel/.ssh..."
    sudo mkdir -pv ${vROOFSDIR}/etc/skel/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/etc/skel/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/etc/skel/.ssh
    sudo chmod 600 ${vROOFSDIR}/etc/skel/.ssh/authorized_keys
    sudo chown -R root:root ${vROOFSDIR}/etc/skel/.ssh

    echo "    [+] Копируем публичный ключ для root..."
    sudo mkdir -pv ${vROOFSDIR}/root/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/root/.ssh
    sudo chmod 600 ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chown -R root:root ${vROOFSDIR}/root/.ssh
else
    echo "    [-] Публичный ключ отсутствует..."
fi

echo "[+] Настраиваем Tmux..."
cat <<TMUXCONF | sudo tee ${vROOFSDIR}/etc/skel/.tmux.conf ${vROOFSDIR}/root/.tmux.conf
setw -g mouse on
set-option -g history-limit 3000000
TMUXCONF

echo "[+] Добавляем HDSentinel..."
HDS_URL="https://www.hdsentinel.com/hdslin/hdsentinel-020c-x64.zip"
HDS_ZIP="/tmp/hdsentinel-020c-x64.zip"
wget --quiet --show-progress ${HDS_URL} -O ${HDS_ZIP}
sudo unzip ${HDS_ZIP} -d ${vROOFSDIR}/usr/local/bin
sudo chmod +x ${vROOFSDIR}/usr/local/bin/HDSentinel
rm -fv ${HDS_ZIP}

#echo "[+] Добавляем Intel® Data Center Diagnostic Tool for Linux* on Intel® Xeon® Processors..."
#echo "    [*] E5 v4 (Broadwell)"
#echo "    [*] E7 v4 (Broadwell)"
#echo "    [*] 1st Scalable (Skylake)"
#echo "    [*] 2nd Scalable (Cascade Lake)"
#echo "    [*] 3rd Scalable (Ice Lake and Cooper Lake)"
#echo "    [*] 4th Scalable (Sapphire Rapids)"
#echo "    [*] 5th Scalable (Emerald Rapids)"
#echo "    [*] Xeon® 6 (Sierra Forest and Granite Rapids)"
#DCDIAG_URL="https://repositories.intel.com/dcdt/dcdiag.x86_64.rpm"
#wget --quiet --show-progress ${DCDIAG_URL} -P ${vROOFSDIR}/opt/

# === ОКОНЧАНИЕ кастомизации ===

sync
sudo sync

if [[ "${vVERSION}" == "8" || "${vVERSION}" == "9" ]]; then
    echo "[+] Размонтируем '${vROOFSDIR}'..."
    sudo umount -fv ${vROOFSDIR}
    echo "[+] Отсоединяем loop-устройство ${vLOOPDEV}..."
    sudo losetup -d ${vLOOPDEV}
fi

cd ..; pwd
echo "[+] Пересобираем squashfs..."
sudo mksquashfs squashfs-root ../LiveOS/squashfs.img -comp xz -b 1M -Xbcj x86 -noappend

cd ..; pwd
echo "[+] Удаляем папку squashfs..."
sudo rm -rf squashfs

echo "[+] Собираем новый ISO..."
if [[ "${vVERSION}" == "8" || "${vVERSION}" == "9" ]]; then
  sudo xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -volid "${vVOLUMEID}" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c ${vBOOTCATALOG} \
  -b ${vBOOTIMG} -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e ${vBOOTEFI} -no-emul-boot \
  .
  echo "    [+] Удаляем папку '${vROOFSDIR}'..."
  sudo rm -rf ${vROOFSDIR}
else
  sudo xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -volid "${vVOLUMEID}" -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e ${vBOOTIMG} -no-emul-boot \
  .
fi

cd ..; pwd

echo "[+] Удаляем '$WORKDIR' '$ISO_INFO'..."
sudo rm -rf $WORKDIR $ISO_INFO

echo "[+] Готово! Новый ISO: $CUSTOM_ISO"
echo "    Доступные пользователи:"
echo "      liveuser / $PASSWORD"
echo "      root     / $ROOTPASS"

diff -u <(xorriso -indev $ISO_NAME -toc -pvd_info) <(xorriso -indev $CUSTOM_ISO -toc -pvd_info)

exit 0
