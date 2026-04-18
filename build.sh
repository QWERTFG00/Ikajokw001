#!/usr/bin/env bash
set -euo pipefail

OS_NAME="ikajokw"
OS_VERSION="1.0.0"
OUTPUT="$(pwd)/${OS_NAME}-${OS_VERSION}.iso"
BUILD_DIR="/tmp/${OS_NAME}-build"
ROOTFS="${BUILD_DIR}/rootfs"
ISO_DIR="${BUILD_DIR}/iso"

sudo rm -rf "${BUILD_DIR}"
mkdir -p "${ROOTFS}" "${ISO_DIR}"/{boot/grub,live}

echo "[1/6] Bootstrapping Debian..."
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=linux-image-amd64,initramfs-tools,systemd-sysv,openssh-server,curl,wget,nano,htop,ca-certificates,sudo,parted,e2fsprogs,dosfstools,grub-pc,grub-efi-amd64,whiptail,rsync \
  bookworm "${ROOTFS}" http://deb.debian.org/debian

echo "[2/6] Configuring system..."
sudo chroot "${ROOTFS}" /bin/bash -c "
  echo '${OS_NAME}' > /etc/hostname
  echo 'root:ikajokw' | chpasswd
  systemctl enable ssh
"

sudo tee "${ROOTFS}/etc/issue" > /dev/null << 'EOF'

  ██╗██╗  ██╗ █████╗      ██╗ ██████╗ ██╗  ██╗██╗    ██╗
  ██║██║ ██╔╝██╔══██╗     ██║██╔═══██╗██║ ██╔╝██║    ██║
  ██║█████╔╝ ███████║     ██║██║   ██║█████╔╝ ██║ █╗ ██║
  ██║██╔═██╗ ██╔══██║██   ██║██║   ██║██╔═██╗ ██║███╗██║
  ██║██║  ██╗██║  ██║╚█████╔╝╚██████╔╝██║  ██╗╚███╔███╔╝
  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚════╝  ╚═════╝ ╚═╝  ╚═╝ ╚══╝╚══╝

  ikajokw OS v1.0.0 (Installer)
  พิมพ์ 'ikajokw-install' เพื่อติดตั้งลง HDD

EOF

echo "[3/6] Creating installer script..."
sudo tee "${ROOTFS}/usr/local/bin/ikajokw-install" > /dev/null << 'INSTALLER'
#!/bin/bash
set -euo pipefail

whiptail --title "ikajokw OS Installer" --msgbox "ยินดีต้อนรับ!\\n\\nกด OK เพื่อเริ่มติดตั้ง" 10 50 || exit 0

DISK_LIST=()
while read -r line; do
  NAME=$(echo "$line" | awk '{print $1}')
  SIZE=$(echo "$line" | awk '{print $2}')
  DISK_LIST+=("$NAME" "$SIZE")
done < <(lsblk -d -o NAME,SIZE -n | grep -v loop)
TARGET=$(whiptail --title "เลือก Disk" --menu "⚠️  ข้อมูลใน disk จะถูกลบ!" 15 50 6 "${DISK_LIST[@]}" 3>&1 1>&2 2>&3) || exit 0
TARGET="/dev/$TARGET"

whiptail --title "ยืนยัน" --yesno "ติดตั้งลง $TARGET ?\\nข้อมูลทั้งหมดจะถูกลบ!" 8 50 || exit 0

parted -s "$TARGET" mklabel gpt \
  mkpart ESP fat32 1MiB 512MiB set 1 esp on \
  mkpart ROOT ext4 512MiB 100%
mkfs.fat -F32 -n IKAJOKW_EFI "${TARGET}1"
mkfs.ext4 -L ikajokw_root "${TARGET}2"

mount "${TARGET}2" /mnt
mkdir -p /mnt/boot/efi
mount "${TARGET}1" /mnt/boot/efi

rsync -a --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/mnt --exclude=/tmp / /mnt/

for d in proc sys dev run; do mount --bind /$d /mnt/$d; done

chroot /mnt /bin/bash -c "
  echo 'root:root' | chpasswd
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ikajokw
  grub-install --target=i386-pc --recheck $TARGET
  update-grub
"

for d in proc sys dev run; do umount /mnt/$d; done
umount /mnt/boot/efi /mnt
whiptail --title "สำเร็จ" --msgbox "ติดตั้งเสร็จ!\\nรีบูตแล้วถอด ISO" 8 50
reboot
INSTALLER

sudo chroot "${ROOTFS}" chmod +x /usr/local/bin/ikajokw-install

echo "[4/6] Creating SquashFS..."
sudo mksquashfs "${ROOTFS}" "${ISO_DIR}/live/filesystem.squashfs" -comp xz -b 1M -noappend

echo "[5/6] Copying kernel..."
sudo cp "${ROOTFS}/boot"/vmlinuz-* "${ISO_DIR}/boot/vmlinuz"
sudo cp "${ROOTFS}/boot"/initrd.img-* "${ISO_DIR}/boot/initrd.img"

echo "[6/6] Building ISO..."
sudo tee "${ISO_DIR}/boot/grub/grub.cfg" > /dev/null << 'EOF'
set default=0
set timeout=5
menuentry "ikajokw OS Installer" {
  linux /boot/vmlinuz root=/dev/sr0 ro
  initrd /boot/initrd.img
}
EOF

sudo grub-mkrescue -o "${OUTPUT}" "${ISO_DIR}"
echo "✅ ISO: ${OUTPUT}"
