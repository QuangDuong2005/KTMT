# # Script tạo file hex cho Verilog ($readmemh-safe)

# input_filename = r"data/20260104.124356-avatar-cute-3_resized.jpeg"
# output_filename = r"data/test.hex"

# try:
#     with open(input_filename, "rb") as f:
#         data = f.read()

#     with open(output_filename, "w") as f:
#         f.write("// JPEG Data Hex File\n")
#         for byte in data:
#             f.write(f"{byte:02X}\n")

#     print(f"✅ Đã tạo xong {output_filename} với {len(data)} bytes.")

# except FileNotFoundError:
#     print(f"❌ Không tìm thấy file {input_filename}")

import sys

def jpg_to_hex(input_jpg, output_hex):
    try:
        with open(input_jpg, 'rb') as f:
            content = f.read()
            
        with open(output_hex, 'w') as f:
            # Ghi từng byte dưới dạng hex, mỗi byte một dòng hoặc cách nhau bởi dấu cách
            for i, byte in enumerate(content):
                f.write(f"{byte:02x} ")
                if (i + 1) % 16 == 0:
                    f.write("\n")
                    
        print(f"Success: Converted '{input_jpg}' to '{output_hex}' ({len(content)} bytes).")
        
    except FileNotFoundError:
        print(f"Error: File '{input_jpg}' not found.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # Thay 'image.jpg' bằng tên file ảnh của bạn
    # Thay 'test.hex' bằng tên file hex bạn muốn tạo
    jpg_to_hex('data/HIeunho.jpeg', 'test.hex')