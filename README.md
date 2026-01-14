file giải mã jpeg bằng verilog 

Một số lưu ý: Nên chạy với ảnh có kích thước dưới 200x200 để không phải chờ quá lâu 
              Nếu ảnh chỉ giải nén được 1 phần do bị ngắt đứt quãng hãy gửi ảnh đó lên ứng dụng Zalo và tải lại ảnh
          
Cách chạy code:
Hãy đảm bảo ảnh của bạn được chuyển sang hex bằng chạy câu lệnh ở trong file data/gentesthex.py

chạy tromg cmd bằng cách di chuyển đến thư mục \jpeg_decoder_verilog> và chạy câu lệnh sau

iverilog -g2012 -o sim/system_test rtl/top/*.v rtl/parser/*.v rtl/entropy/*.v rtl/transform/*.v rtl/color/*.v rtl/utils/*.v tb/tb_jpeg_decoder_top.v
vvp sim/system_test


đầu ra sẽ là file 
output_image.ppm
