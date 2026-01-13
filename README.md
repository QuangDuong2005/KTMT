file giải mã jpeg bằng verilog 
jpeg loại SOF2
chạy tromg cmd bằng cách di chuyển đến thư mục \jpeg_decoder_verilog> và chạy câu lệnh sau
iverilog -g2012 -o sim/system_test rtl/top/*.v rtl/parser/*.v rtl/entropy/*.v rtl/transform/*.v rtl/color/*.v rtl/utils/*.v tb/tb_jpeg_decoder_top.v
vvp sim/system_test
đầu ra sẽ là file 
output_image.ppm
