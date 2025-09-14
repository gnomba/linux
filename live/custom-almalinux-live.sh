#!/bin/bash
set -e

# === Выбор версии AlmaLinux ===
echo "Выберите версию AlmaLinux Live ISO:"
echo "8) 8"
echo "9) 9"
echo "10) 10"
read -p "Введите номер версии [1-4]: " VERSION

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
mkdir -p "$WORKDIR" "$MOUNTDIR"

echo "[+] Скачиваем ISO..."
[ -f "$ISO_NAME" ] || curl -L "$ISO_URL" -o "$ISO_NAME"

echo "[+] Монтируем ISO..."
sudo mount -o loop "$ISO_NAME" "$MOUNTDIR"

echo "[+] Копируем содержимое ISO..."
rsync -a "$MOUNTDIR/" "$WORKDIR/"

sudo umount "$MOUNTDIR"

cd "$WORKDIR"

echo "[+] Распаковываем squashfs..."
mkdir squashfs
cd squashfs
unsquashfs ../LiveOS/squashfs.img
cd squashfs-root

echo "[+] Настраиваем sshd..."
# Включаем root, пароль и ключи
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' etc/ssh/sshd_config

echo "[+] Добавляем systemd unit для SSH..."
cat <<EOF | sudo tee etc/systemd/system/live-ssh.service
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

sudo ln -s /etc/systemd/system/live-ssh.service etc/systemd/system/multi-user.target.wants/live-ssh.service

# === Добавляем ключи ===
if [ -f "$PUBKEY_FILE" ]; then
    echo "[+] Копируем публичный ключ для liveuser..."
    sudo mkdir -p home/liveuser/.ssh
    sudo cp "$PUBKEY_FILE" home/liveuser/.ssh/authorized_keys
    sudo chmod 700 home/liveuser/.ssh
    sudo chmod 600 home/liveuser/.ssh/authorized_keys
    sudo chown -R 1000:1000 home/liveuser/.ssh  # UID/GID liveuser

    echo "[+] Копируем публичный ключ для root..."
    sudo mkdir -p root/.ssh
    sudo cp "$PUBKEY_FILE" root/.ssh/authorized_keys
    sudo chmod 700 root/.ssh
    sudo chmod 600 root/.ssh/authorized_keys
    sudo chown -R 0:0 root/.ssh
fi

echo "[+] Пересобираем squashfs..."
cd ..
sudo mksquashfs squashfs-root ../LiveOS/squashfs.img -comp xz -b 1M -Xbcj x86 -noappend

cd ..

echo "[+] Собираем новый ISO..."
xorriso -as mkisofs -o "../$CUSTOM_ISO" \
  -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
  .

echo "[+] Готово! Новый ISO: $CUSTOM_ISO"
echo "    Доступные пользователи:"
echo "      liveuser / $PASSWORD"
echo "      root     / $ROOTPASS"
