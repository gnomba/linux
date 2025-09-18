#!/bin/bash
set -e

# === Выбор версии AlmaLinux ===
echo "Выберите версию AlmaLinux Live ISO:"
echo "8) 8"
echo "9) 9"
echo "10) 10"
read -p "Введите номер версии [8-10]: " VERSION

case $VERSION in
  8) ISO_URL="https://repo.almalinux.org/almalinux/$VERSION/live/x86_64/AlmaLinux-$VERSION-latest-x86_64-Live-GNOME-Mini.iso" ;;
  9) ISO_URL="https://repo.almalinux.org/almalinux/$VERSION/live/x86_64/AlmaLinux-$VERSION-latest-x86_64-Live-GNOME-Mini.iso" ;;
  10) ISO_URL="https://repo.almalinux.org/almalinux/$VERSION/live/x86_64/AlmaLinux-$VERSION-latest-x86_64-Live-GNOME.iso" ;;
  *) echo "Неверный выбор"; exit 1 ;;
esac

# === Параметры ===
ISO_NAME="AlmaLinux-$VERSION-live-original.iso"
CUSTOM_ISO="AlmaLinux-$VERSION-live-ssh.iso"
WORKDIR="$PWD/almalinux-live"
MOUNTDIR="$PWD/iso-mount"

PASSWORD="livepass"    # пароль для пользователя liveuser
ROOTPASS="rootpass"    # пароль для root
PUBKEY_FILE="$HOME/.ssh/id_rsa.pub"  # ваш публичный ключ

# === Подготовка ===
mkdir -pv "$WORKDIR" "$MOUNTDIR"

echo "[+] Скачиваем ISO... ("$ISO_URL" --> "$ISO_NAME")"
[ -f "$ISO_NAME" ] || curl -L "$ISO_URL" -o "$ISO_NAME"

echo "[+] Монтируем ISO... ("$ISO_NAME" --> "$MOUNTDIR")"
sudo mount -o loop "$ISO_NAME" "$MOUNTDIR"

echo "[+] Копируем содержимое ISO... ("$MOUNTDIR/" --> "$WORKDIR/")"
sudo rsync -a "$MOUNTDIR/" "$WORKDIR/"

sudo umount -v "$MOUNTDIR"

cd "$WORKDIR"

echo "[+] Распаковываем squashfs..."
sudo mkdir squashfs
cd squashfs
sudo unsquashfs ../LiveOS/squashfs.img
cd squashfs-root

if [[ "$VERSION" == "8" || "$VERSION" == "9" ]]; then
    sudo losetup --find --partscan --show LiveOS/rootfs.img 
    vLOOPDEV="$(sudo losetup -l | grep rootfs | awk '{print $1}')"
    vROOFSDIR="/mnt/rootfs"
    sudo mkdir -pv ${vROOFSDIR}
    sudo mount -v ${vLOOPDEV} ${vROOFSDIR}
else
    vROOFSDIR="."
fi

echo "[+] Настраиваем sshd..."
# Включаем root, пароль и ключи
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' ${vROOFSDIR}/etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' ${vROOFSDIR}/etc/ssh/sshd_config

echo "[+] Добавляем systemd unit для SSH..."
cat <<EOF | sudo tee ${vROOFSDIR}/etc/systemd/system/live-ssh.service
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
EOF

sudo ln -s /etc/systemd/system/live-ssh.service ${vROOFSDIR}/etc/systemd/system/multi-user.target.wants/live-ssh.service

# === Добавляем ключи ===
if [ -f "$PUBKEY_FILE" ]; then
    echo "[+] Копируем публичный ключ для liveuser..."
    sudo mkdir -pv ${vROOFSDIR}/home/liveuser/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/home/liveuser/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/home/liveuser/.ssh
    sudo chmod 600 ${vROOFSDIR}/home/liveuser/.ssh/authorized_keys
    sudo chown -R 1000:1000 ${vROOFSDIR}/home/liveuser/.ssh  # UID/GID liveuser

    echo "[+] Копируем публичный ключ для root..."
    sudo mkdir -pv ${vROOFSDIR}/root/.ssh
    sudo cp "$PUBKEY_FILE" ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chmod 700 ${vROOFSDIR}/root/.ssh
    sudo chmod 600 ${vROOFSDIR}/root/.ssh/authorized_keys
    sudo chown -R 0:0 ${vROOFSDIR}/root/.ssh
else
    echo "[-] Публичный ключ для liveuser/root отсутствует..."
fi

echo "[+] Настраиваем TMUX..."
cat <<EOA | sudo tee ${vROOFSDIR}/home/liveuser/.tmux.conf ${vROOFSDIR}/root/.tmux.conf
setw -g mouse on
set-option -g history-limit 3000000
EOA

echo "[+] Добавляем HDSentinel..."
wget https://www.hdsentinel.com/hdslin/hdsentinel-020c-x64.zip -O /tmp/hdsentinel-020c-x64.zip
sudo unzip /tmp/hdsentinel-020c-x64.zip -d ${vROOFSDIR}/usr/local/bin
sudo chmod +x ${vROOFSDIR}/usr/local/bin/HDSentinel

sync
sudo sync

if [[ "$VERSION" == "8" || "$VERSION" == "9" ]]; then
    sudo umount -fv ${vROOFSDIR}
    sudo losetup -d ${vLOOPDEV}
fi

echo "[+] Пересобираем squashfs..."
cd ..
sudo mksquashfs squashfs-root ../LiveOS/squashfs.img -comp xz -b 1M -Xbcj x86 -noappend

cd ..

sudo rm -rfv squashfs

echo "[+] Собираем новый ISO..."
if [[ "$VERSION" == "8" || "$VERSION" == "9" ]]; then
  sudo xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -isohybrid-mbr isolinux/isolinux.bin \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
  .
  sudo rm -rfv ${vROOFSDIR}
else
  sudo xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e images/eltorito.img -no-emul-boot \
  .
fi

cd ..
sudo rm -rfv $WORKDIR $MOUNTDIR

echo "[+] Готово! Новый ISO: $CUSTOM_ISO"
echo "    Доступные пользователи:"
echo "      liveuser / $PASSWORD"
echo "      root     / $ROOTPASS"
