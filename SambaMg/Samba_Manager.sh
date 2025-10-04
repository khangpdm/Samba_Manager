AutoScripts Samba

#!/bin/bash
# samba_manager.sh - Menu quản lý Samba
# Chạy bằng root hoặc sudo

SMB_CONF="/etc/samba/smb.conf"
SMB_BACKUP_DIR="/etc/samba/backup"
SMB_SHARE_BASE="/srv/samba"

DNS_ZONE_DIR="/var/named"
DNS_CONF="/etc/named.conf"

mkdir -p "$SMB_BACKUP_DIR"
mkdir -p "$SMB_SHARE_BASE"

pause(){ read -p "Nhấn Enter để tiếp tục..."; }

### --- SAMBA FUNCTIONS --- ###

install_basic_samba(){
  echo "Cài Samba và công cụ cần thiết..."
  dnf install -y samba samba-client samba-common policycoreutils-python-utils firewalld bind bind-utils
  systemctl enable --now firewalld

  # Backup cấu hình cũ
  cp "$SMB_CONF" "$SMB_BACKUP_DIR/smb.conf.$(date +%F_%H%M%S)" 2>/dev/null || true

  # Cấu hình Samba cơ bản (không có share mặc định)
  cat > "$SMB_CONF" <<EOF
[global]
   workgroup = WORKGROUP
   server string = Samba Server %v
   netbios name = fileserver
   security = user
   map to guest = Bad User
   dns proxy = no
EOF

  mkdir -p /srv/samba
  chown -R nobody:nobody /srv/samba
  chmod -R 0775 /srv/samba

  # SELinux
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t samba_share_t "/srv/samba(/.*)?"
    restorecon -Rv /srv/samba
  fi

  # firewall
  firewall-cmd --permanent --add-service=samba
  firewall-cmd --reload

  systemctl enable --now smb nmb
  echo "Cài & cấu hình Samba cơ bản xong (chưa có share, hãy dùng menu để thêm)."
  pause
}


add_share(){
  read -p "Tên share (ví dụ Documents): " sharename
  read -p "Đường dẫn (ví dụ /srv/samba/docs): " path
  read -p "Cho phép guest truy cập? (y/n): " guest

  mkdir -p "$path"

  if [[ $guest =~ ^[Yy]$ ]]; then
    ACCESS="guest ok = yes
   read only = no"
    chown nobody:nobody "$path"
    chmod 0777 "$path"
  else
    read -p "Tên user Samba hợp lệ (đã tạo): " smbuser
    ACCESS="guest ok = no
   valid users = $smbuser
   read only = no"
    chown $smbuser:$smbuser "$path"
    chmod 0700 "$path"
  fi

  cat >> "$SMB_CONF" <<EOF

# SAMBA-MANAGER-SHARE-BEGIN:$sharename
[$sharename]
   path = $path
   browseable = yes
   writable = yes
   $ACCESS
# SAMBA-MANAGER-SHARE-END:$sharename
EOF

  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t samba_share_t "${path}(/.*)?"
    restorecon -Rv "$path"
  fi

  systemctl restart smb nmb
  echo "Đã thêm share $sharename"
  pause
}


remove_share(){
  read -p "Tên share cần xóa: " sharename
  sed -i "/# SAMBA-MANAGER-SHARE-BEGIN:$sharename/,/# SAMBA-MANAGER-SHARE-END:$sharename/d" "$SMB_CONF"
  systemctl restart smb nmb
  echo "Đã xóa share $sharename từ cấu hình."
  read -p "Bạn có muốn xóa thư mục vật lý không? (y/n): " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    read -p "Nhập đường dẫn thư mục để xóa: " path
    rm -rf "$path"
    echo "Đã xóa thư mục $path"
  fi
  pause
}

add_user(){
  read -p "Tên user Samba (sẽ tạo Linux user nếu chưa tồn tại): " user
  id -u "$user" &>/dev/null || useradd -M -s /sbin/nologin "$user"
  echo "Nhập mật khẩu Samba cho $user:"
  read -s -p "Password: " PASS; echo
  read -s -p "Nhập lại Password: " PASS2; echo
  if [[ "$PASS" != "$PASS2" ]]; then
    echo "Password không khớp. Hủy."
    pause; return
  fi
  printf "%s\n%s\n" "$PASS" "$PASS" | smbpasswd -s -a "$user"
  smbpasswd -e "$user"
  echo "Đã thêm user $user."
  pause
}

remove_user(){
  read -p "Tên user Samba cần xóa: " user
  smbpasswd -x "$user" || true
  read -p "Xóa Linux user $user luôn không? (y/n): " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    userdel "$user" 2>/dev/null || echo "Không thể xóa Linux user (có thể không tồn tại)."
  fi
  echo "Đã xóa user $user khỏi Samba."
  pause
}

restart_samba(){
  systemctl restart smb nmb
  echo "Đã restart smb & nmb."
  pause
}

check_status(){
  systemctl status smb --no-pager
  echo
  testparm
  echo
  echo "Liệt kê share (localhost):"
  smbclient -L //localhost -U% || true
  pause
}

backup_config(){
  cp "$SMB_CONF" "$SMB_BACKUP_DIR/smb.conf.$(date +%F_%H%M%S).bak"
  echo "Backup lưu tại $SMB_BACKUP_DIR"
  pause
}

### --- DNS FUNCTIONS (BIND) --- ###

configure_dns(){
  read -p "Nhập tên domain (ví dụ company.local): " DOMAIN
  read -p "Nhập IP server (ví dụ 192.168.2.37): " IPADDR
  ZONE_FILE="${DNS_ZONE_DIR}/${DOMAIN}.zone"

  echo ">>> Cấu hình BIND cho $DOMAIN với IP $IPADDR ..."

  # Backup named.conf
  cp "$DNS_CONF" "$DNS_CONF.bak.$(date +%F_%H%M%S)" 2>/dev/null || true

  # Ghi file named.conf chuẩn (chỉ 1 block options)
  cat > "$DNS_CONF" <<EOF
options {
    directory "/var/named";
    listen-on port 53 { any; };
    listen-on-v6 { any; };

    allow-query { any; };
    recursion yes;

    # Forward ra Internet nếu domain không nằm trong zone cục bộ
    forward only;
    forwarders { 8.8.8.8; 1.1.1.1; };
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};
EOF

  # Forward zone file
  cat > "$ZONE_FILE" <<EOF
\$TTL 86400
@   IN  SOA ns1.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d%H) ; Serial
        3600 ; Refresh
        1800 ; Retry
        1209600 ; Expire
        86400 ) ; Minimum TTL

; Name server
@       IN  NS  ns1.${DOMAIN}.

; A records
ns1     IN  A   ${IPADDR}
www     IN  A   ${IPADDR}
EOF

  # Thêm zone nội bộ vào named.conf
  cat >> "$DNS_CONF" <<EOF

zone "${DOMAIN}" IN {
    type master;
    file "${ZONE_FILE}";
    allow-update { none; };
};
EOF

  # Reverse zone
  REVIP=$(echo $IPADDR | awk -F. '{print $3"."$2"."$1}')
  LASTOCTET=$(echo $IPADDR | awk -F. '{print $4}')
  REVZONE="${REVIP}.in-addr.arpa"
  REV_FILE="${DNS_ZONE_DIR}/${REVZONE}.zone"

  cat > "$REV_FILE" <<EOF
\$TTL 86400
@   IN  SOA ns1.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d%H) ; Serial
        3600 ; Refresh
        1800 ; Retry
        1209600 ; Expire
        86400 ) ; Minimum TTL

; Name server
@   IN  NS  ns1.${DOMAIN}.

; PTR record
${LASTOCTET}   IN  PTR www.${DOMAIN}.
EOF

  # Thêm reverse zone vào named.conf
  cat >> "$DNS_CONF" <<EOF

zone "${REVZONE}" IN {
    type master;
    file "${REV_FILE}";
    allow-update { none; };
};
EOF

  # Quyền cho file zone
  chown root:named "$ZONE_FILE" "$REV_FILE"
  chmod 640 "$ZONE_FILE" "$REV_FILE"

  # Mở firewall cho DNS
  firewall-cmd --permanent --add-service=dns
  firewall-cmd --reload

  echo ">>> Kiểm tra cú pháp..."
  named-checkconf
  named-checkzone "$DOMAIN" "$ZONE_FILE"
  named-checkzone "$REVZONE" "$REV_FILE"

  echo ">>> Restart dịch vụ BIND..."
  systemctl enable --now named
  systemctl restart named

  echo ">>> Hoàn tất: DNS cho $DOMAIN đã sẵn sàng."
  pause
}



### --- MAIN MENU --- ###

while true; do
  clear
  cat <<EOF
==========================
  Samba + DNS Management
==========================
1. Cài đặt & cấu hình Samba cơ bản
2. Thêm share mới
3. Xóa share
4. Thêm user Samba
5. Xóa user Samba
6. Restart Samba
7. Kiểm tra trạng thái Samba
8. Backup cấu hình Samba
9. Cấu hình DNS (BIND: forward + reverse)
10. Thoát
==========================
EOF
  read -p "Chọn [1-10]: " choice
  case $choice in
    1) install_basic_samba ;;
    2) add_share ;;
    3) remove_share ;;
    4) add_user ;;
    5) remove_user ;;
    6) restart_samba ;;
    7) check_status ;;
    8) backup_config ;;
    9) configure_dns ;;
    10) echo "Thoát..."; exit 0 ;;
    *) echo "Lựa chọn không hợp lệ"; pause ;;
  esac
done




