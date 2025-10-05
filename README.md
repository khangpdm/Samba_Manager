[HuongDanSuDung.md](https://github.com/user-attachments/files/22709921/HuongDanSuDung.md)
# Hướng dẫn sử dụng script Samba + DNS

Hướng dẫn sử dụng script Samba + DNS  
1) Yêu cầu hệ thống & chu ẩn bị 
- Hệ điều hành: CentOS Stream 8/9 . 
- Quyền: chạy bằng root ho ặc sudo.  
- Kết nối mạng để cài gói từ repo.  
- SELinux b ật/enforcing vẫn dùng được (script đã gán context chia sẻ Samba).  
- tắt Firewalld ở máy ảo và máy thật 
 
Lưu file & c ấp quy ền: 
 
sudo mkdir -p /opt/scripts  
sudo vi /opt/scripts/samba_manager.sh  # dán nội dung script của bạn 
sudo chmod +x /opt/scripts/samba_manager.sh  
 
Chạy script:  
sudo /opt/scripts/samba_manager.sh  
2) Giao diện & luồng làm việc 
Script có menu quản lý:  
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
3) Ch ức năng chi ti ết 
- [1] Cài đặt & cấu hình Samba cơ bản: cài gói, mở firewall, cấu hình share mặc định. 
- [2] Thêm share mới: nhập tên share + đường dẫn, script thêm vào smb.conf, phân quyền. 
- [3] Xóa share: xóa block trong smb.conf, tùy ch ọn xóa thư mục vật lý. 
- [4] Thêm user Samba: tạo user Linux (nếu chưa có), thêm vào Samba.  
- [5] Xóa user Samba: xóa user khỏi Samba, tùy chọn xóa user Linux.  
- [6] Restart Samba: restart smb, nmb.  
- [7] Kiểm tra trạng thái Samba: systemctl status, testparm, smbclient.  
- [8] Backup cấu hình Samba: copy smb.conf sang thư mục backup.  
- [9] Cấu hình DNS: tạo forward & reverse zone, sửa named.conf, restart named.  
4) Kịch bản mẫu sử dụng 
Ví dụ chia s ẻ thư mục cho Windows:  
1. Ch ạy [1] để cài Samba cơ bản. 
2. Ch ạy [4] tạo user Samba (vd: smbuser).  
3. Ch ạy [2] tạo share mới (vd: Projects).  
4. Truy cập từ Windows: \\<IP_CentOS> \Projects.  
 
Ví dụ cấu hình DNS:  
1. Chạy [9], nhập domain `company.local`, IP `192.168.2.37`.  
2. Trên Windows, đặt DNS = 192.168.2.37.  
3. Kiểm tra bằng nslookup www.company.local.  
5) Kiểm tra & xác th ực 
- Samba:  
 
systemctl is -active smb  
testparm  
smbclient -L //localhost -U% 
 
- DNS:  
 
dig @127.0.0.1 www.domain.local A +short  
dig @127.0.0.1 -x <ip> +short  
 
*Lưu ý nếu bị lỗi như này thì : 
 
Đây là lỗi do window không cho phép đăng nhập nhiều tài khoản trên cùng môt m áy. 
Mở command propt và nh ập lệnh: 
net use * /delete /y  
Sau đó truy nh ập lại folder , đăng nhập bằng tài khoản được cấp quyền.
