# Script tạo file hex cho Verilog ($readmemh-safe)

input_filename = "data/20260101.172947-pexels-pixabay-162140_resized (1).jpeg"
output_filename = "data/test.hex"

try:
    with open(input_filename, "rb") as f:
        data = f.read()

    with open(output_filename, "w") as f:
        f.write("// JPEG Data Hex File\n")
        for byte in data:
            f.write(f"{byte:02X}\n")

    print(f"✅ Đã tạo xong {output_filename} với {len(data)} bytes.")

except FileNotFoundError:
    print(f"❌ Không tìm thấy file {input_filename}")
