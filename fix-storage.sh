#!/bin/bash
set -e

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Jalankan script ini sebagai root (sudo)!"
  exit 1
fi

echo "[*] Mengupdate dan memastikan tools terinstall..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq cloud-guest-utils fdisk util-linux e2fsprogs xfsprogs lvm2 >/dev/null 2>&1 || true

# 1. Deteksi partisi root & filesystem type
ROOT_PART=$(findmnt -n -o SOURCE /)
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

echo "[+] Root partition: $ROOT_PART ($ROOT_FSTYPE)"

# 2. Cek apakah root menggunakan LVM atau Partisi Biasa
if [[ "$ROOT_PART" == /dev/mapper/* ]]; then
    echo "[*] Deteksi LVM..."
    LV_PATH="$ROOT_PART"
    VG_NAME=$(lvs --noheadings -o vg_name "$LV_PATH" | tr -d ' ')
    PV_NAME=$(pvs --noheadings -o pv_name -S "vg_name=$VG_NAME" | tr -d ' ')
    
    # Ambil nama disk induk dan nomor partisi PV
    DISK_NAME=$(lsblk -no PKNAME "$PV_NAME" | head -n 1)
    PART_NUM=$(echo "$PV_NAME" | grep -o '[0-9]*$')
    
    if [ -n "$DISK_NAME" ] && [ -n "$PART_NUM" ]; then
        echo "[*] Resizing disk partition: /dev/$DISK_NAME partisi $PART_NUM"
        growpart "/dev/$DISK_NAME" "$PART_NUM" || true
    fi
    
    echo "[*] Resizing Physical Volume & Logical Volume..."
    pvresize "$PV_NAME" || true
    lvextend -l +100%FREE "$LV_PATH" || true
    
    echo "[*] Resizing Filesystem..."
    if [ "$ROOT_FSTYPE" = "ext4" ] || [ "$ROOT_FSTYPE" = "ext3" ]; then
        resize2fs "$LV_PATH"
    elif [ "$ROOT_FSTYPE" = "xfs" ]; then
        xfs_growfs /
    fi

else
    # Partisi Standar (non-LVM, e.g. /dev/vda1, /dev/sda1)
    DISK_NAME=$(lsblk -no PKNAME "$ROOT_PART" | head -n 1)
    PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')
    
    if [ -z "$DISK_NAME" ] || [ -z "$PART_NUM" ]; then
        echo "[-] Gagal mendeteksi nama disk/partisi induk."
        exit 1
    fi
    
    echo "[*] Resizing partisi /dev/$DISK_NAME $PART_NUM..."
    growpart "/dev/$DISK_NAME" "$PART_NUM" || true
    
    echo "[*] Resizing Filesystem..."
    if [ "$ROOT_FSTYPE" = "ext4" ] || [ "$ROOT_FSTYPE" = "ext3" ]; then
        resize2fs "$ROOT_PART"
    elif [ "$ROOT_FSTYPE" = "xfs" ]; then
        xfs_growfs /
    fi
fi

echo ""
echo "[✓] Selesai! Storage berhasil disesuaikan:"
df -h /
