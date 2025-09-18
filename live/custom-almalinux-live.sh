#!/bin/bash

set -x

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
CUSTOM_ISO="AlmaLinux-${vVERSION}-${vARCH}-live-ssh.iso"
WORKDIR="$PWD/almalinux-live"
MOUNTDIR="$PWD/iso-mount"

PASSWORD="livepass"    # пароль для пользователя liveuser
ROOTPASS="rootpass"    # пароль для root
PUBKEY_FILE="$HOME/.ssh/id_rsa.pub"  # ваш публичный ключ

# === Подготовка ===
echo "[+] Создаём папки '$WORKDIR' '$MOUNTDIR'..."
mkdir -pv "$WORKDIR" "$MOUNTDIR"

echo "[+] Скачиваем ISO..."
echo "    [+] $ISO_URL --> $ISO_NAME"
vCURL_OPTS="-s --progress-bar --user-agent \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36\" -L"
[ -f "$ISO_NAME" ] || curl ${vCURL_OPTS} "$ISO_URL" -o "$ISO_NAME"

echo "[+] Монтируем ISO..."
echo "    [+] $ISO_NAME --> $MOUNTDIR"
sudo mount -o loop "$ISO_NAME" "$MOUNTDIR"

echo "[+] Копируем содержимое ISO..."
echo "    [+] $MOUNTDIR/ --> $WORKDIR/)"
sudo rsync -a "$MOUNTDIR/" "$WORKDIR/"

echo "[+] Размонтируем ISO..."
sudo umount -v "$MOUNTDIR"

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
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' ${vROOFSDIR}/etc/ssh/sshd_config

echo "[+] Добавляем systemd unit для SSH..."
cat <<EOA | sudo tee ${vROOFSDIR}/etc/systemd/system/live-ssh.service
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
EOA

sudo ln -s /etc/systemd/system/live-ssh.service ${vROOFSDIR}/etc/systemd/system/multi-user.target.wants/live-ssh.service

echo "[+] Добавляем ключи..."
if [ -f "$PUBKEY_FILE" ]; then
    echo "    [+] Копируем публичный ключ для liveuser..."
    sudo mkdir -pv ${vROOFSDIR}/home/liveuser/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/home/liveuser/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/home/liveuser/.ssh
    sudo chmod 600 ${vROOFSDIR}/home/liveuser/.ssh/authorized_keys
    sudo chown -R 1000:1000 ${vROOFSDIR}/home/liveuser/.ssh  # UID/GID liveuser

    echo "    [+] Копируем публичный ключ для root..."
    sudo mkdir -pv ${vROOFSDIR}/root/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/root/.ssh
    sudo chmod 600 ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chown -R 0:0 ${vROOFSDIR}/root/.ssh
else
    echo "    [-] Публичный ключ для liveuser/root отсутствует..."
fi

echo "[+] Настраиваем Tmux..."
cat <<EOB | sudo tee ${vROOFSDIR}/home/liveuser/.tmux.conf ${vROOFSDIR}/root/.tmux.conf
setw -g mouse on
set-option -g history-limit 3000000
EOB

echo "[+] Добавляем HDSentinel..."
wget https://www.hdsentinel.com/hdslin/hdsentinel-020c-x64.zip -O /tmp/hdsentinel-020c-x64.zip
sudo unzip /tmp/hdsentinel-020c-x64.zip -d ${vROOFSDIR}/usr/local/bin
sudo chmod +x ${vROOFSDIR}/usr/local/bin/HDSentinel
rm -fv /tmp/hdsentinel-020c-x64.zip
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
  -isohybrid-mbr isolinux/isolinux.bin \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
  .
  echo "    [+] Удаляем папку '${vROOFSDIR}'..."
  sudo rm -rf ${vROOFSDIR}
else
  sudo xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e images/eltorito.img -no-emul-boot \
  .
fi

cd ..; pwd

echo "[+] Удаляем папки '$WORKDIR' '$MOUNTDIR'..."
sudo rm -rf $WORKDIR $MOUNTDIR

echo "[+] Готово! Новый ISO: $CUSTOM_ISO"
echo "    Доступные пользователи:"
echo "      liveuser / $PASSWORD"
echo "      root     / $ROOTPASS"

exit 0
