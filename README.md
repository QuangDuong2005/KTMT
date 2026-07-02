# Bộ Giải Mã Ảnh JPEG Bằng Ngôn Ngữ Phần Cứng Verilog (JPEG Decoder)

Dự án này triển khai một bộ giải mã ảnh JPEG (JPEG Decoder) hoàn chỉnh ở cấp độ phần cứng (RTL) sử dụng ngôn ngữ **Verilog (IEEE 1800-2012 / Verilog 2012)**. Hệ thống nhận đầu vào là luồng bitstream của file ảnh JPEG mã hóa, tự động phân tích cấu trúc Header, thực hiện các thuật toán giải mã entropy, biến đổi toán học ngược để khôi phục không gian màu và xuất ra file ảnh định dạng **PPM (Portable Pixmap)** không nén.

---

## 🛠️ Tính Năng Của Bộ Giải Mã

- **Phân tích Header Tự Động:** Nhận diện và xử lý chính xác các Marker tiêu chuẩn của JPEG như `SOI`, `APP0`, `DQT`, `DHT`, `SOF0`, `SOS`, và `EOI`.
- **Giải Mã Entropy (Huffman Decoding):** Tự động xây dựng cây cấu trúc Huffman từ dữ liệu trong Header và giải mã luồng bitstream động để khôi phục hệ số DC/AC cho từng khối block 8x8.
- **Xử Lý Khối Lượng Tử Ngược & Zigzag:** Sắp xếp lại ma trận 64 phần tử từ chuỗi tuyến tính về ma trận 2D 8x8, đồng thời thực hiện Lượng tử hóa ngược (Dequantization).
- **Biến Đổi IDCT 2D (2D Inverse Discrete Cosine Transform):** Thực hiện tính toán IDCT hai chiều trên block 8x8 bằng cách chia tách thành 2 lần biến đổi IDCT 1D.
- **Chuyển Đổi Không Gian Màu:** Khôi phục dữ liệu từ không gian màu ảnh nén `YCbCr` sang không gian màu hiển thị `RGB` chuẩn 24-bit.

---

## 📂 Cấu Trúc Thư Mục Dự Án

```text
├── data/                      # Thư mục chứa ảnh và script xử lý
│   ├── gentesthex.py          # Script Python chuyển file ảnh (.jpg) thành mã Hex (.hex)
│   └── *.jpg / *.jpeg         # Các ảnh mẫu dùng để test
├── rtl/                       # Mã nguồn thiết kế phần cứng (Verilog)
│   ├── top/                   # Khối xử lý trung tâm cấp cao nhất
│   ├── parser/                # Bộ đọc bitstream và phân tích Header
│   ├── entropy/               # Khối giải mã Entropy và Huffman
│   ├── transform/             # Khối xử lý Zigzag, Dequantization và IDCT
│   ├── color/                 # Khối chuyển đổi không gian màu YCbCr sang RGB
│   └── utils/                 # Các khối tiện ích (tích lũy hệ số, quản lý MCU...)
├── tb/                        # Các file Testbench mô phỏng kiểm thử
│   └── tb_jpeg_decoder_top.v  # Testbench tổng thể cho toàn hệ thống
└── sim/                       # Thư mục chứa file thực thi mô phỏng và dạng sóng
```

---

## 🚀 Hướng Dẫn Chạy Code

Hệ thống được thiết kế để biên dịch và mô phỏng thông qua **Icarus Verilog (iverilog)**. Để chạy dự án, hãy thực hiện lần lượt các bước sau:

### Bước 1: Chuẩn bị dữ liệu ảnh
Phần cứng cần đọc ảnh dưới dạng mã Hex. Hãy chuyển đổi ảnh `.jpg` của bạn thành file `.hex` bằng script Python có sẵn:
1. Đặt ảnh cần test vào thư mục `data/` (và sửa tên file trong file `gentesthex.py` nếu cần).
2. Chạy câu lệnh sau trong terminal:
```bash
cd data
python gentesthex.py
```
*(Đảm bảo đã tạo thành công file test chứa mã Hex làm đầu vào cho testbench)*.

### Bước 2: Biên dịch mã nguồn Verilog
Mở Terminal/Command Prompt tại thư mục gốc của dự án (`jpeg_decoder_verilog`) và chạy lệnh sau để gom và biên dịch toàn bộ các file Verilog:
```bash
iverilog -g2012 -o sim/system_test rtl/top/*.v rtl/parser/*.v rtl/entropy/*.v rtl/transform/*.v rtl/color/*.v rtl/utils/*.v tb/tb_jpeg_decoder_top.v
```

### Bước 3: Chạy mô phỏng
Thực thi file vừa biên dịch để hệ thống bắt đầu quá trình giải mã:
```bash
vvp sim/system_test
```

### Bước 4: Kiểm tra kết quả
Sau khi lệnh chạy xong, hệ thống sẽ tự động xuất ra một file hình ảnh tên là **`output_image.ppm`** ngay tại thư mục bạn đang đứng. Bạn có thể mở file này bằng các phần mềm xem ảnh (Photoshop, GIMP) hoặc các Extension hỗ trợ đọc đuôi `.ppm` trên VS Code.

---

## ⚠️ Một Số Lưu Ý Quan Trọng

1. **Kích thước ảnh khuyến nghị:** Nên chạy với ảnh có kích thước nhỏ (**dưới 200x200 pixel**) để không phải chờ đợi quá lâu. Việc mô phỏng xử lý logic phần cứng (RTL Simulation) tốn rất nhiều tài nguyên máy tính, ảnh càng lớn thời gian chạy sẽ càng lâu.
2. **Xử lý lỗi ảnh bị ngắt quãng hoặc lỗi nén cấu trúc:** Nếu ảnh chỉ giải nén được 1 phần do bị ngắt đứt quãng, nguyên nhân thường là do cấu trúc Huffman hoặc Header của ảnh bị các phần mềm tối ưu hóa làm sai lệch.
   * **Cách khắc phục:** Hãy **gửi ảnh đó lên ứng dụng Zalo**, sau đó **tải lại ảnh** về máy rồi mới dùng Python chuyển sang file Hex. Việc này giúp Zalo tự động chuẩn hóa lại cấu trúc Header và định dạng Huffman của ảnh về chuẩn cơ bản nhất.
