
import numpy as np
import math

# --- UTILITIES ---
def clamp(val, min_val, max_val):
    return max(min(val, max_val), min_val)

def read_hex_file(filepath):
    """Đọc file hex (format text) và trả về list bytes"""
    hex_data = []
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split()
            for p in parts:
                hex_data.append(int(p, 16))
    return hex_data

# --- ZIGZAG TABLE ---
ZIGZAG = [
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63
]

class BitStream:
    def __init__(self, data):
        self.data = data
        self.byte_pos = 0
        self.bit_pos = 0 # 0-7, 7 is MSB

    def read_bit(self):
        if self.byte_pos >= len(self.data):
            return 0 # End of stream
        b = self.data[self.byte_pos]
        val = (b >> (7 - self.bit_pos)) & 1
        
        self.bit_pos += 1
        if self.bit_pos == 8:
            self.bit_pos = 0
            self.byte_pos += 1
            # Handle 0xFF 0x00 stuffing in Scan Data
            if self.byte_pos < len(self.data):
                if self.data[self.byte_pos-1] == 0xFF and self.data[self.byte_pos] == 0x00:
                    self.byte_pos += 1
                elif self.data[self.byte_pos-1] == 0xFF and self.data[self.byte_pos] != 0x00:
                     pass
        return val

    def read_bits(self, n):
        val = 0
        for _ in range(n):
            val = (val << 1) | self.read_bit()
        return val
    
    def align_byte(self):
        if self.bit_pos != 0:
            self.bit_pos = 0
            self.byte_pos += 1

class JPEGDecoderModel:
    def __init__(self, hex_inputs):
        self.data = hex_inputs
        self.pos = 0
        self.img_width = 0
        self.img_height = 0
        self.num_components = 0
        self.components = [] # {id, h, v, q_id}
        self.quant_tables = {} # id -> [64]
        self.huff_tables = {'DC': {}, 'AC': {}} # {id -> {counts, symbols}}
        
        # Files
        self.f_header = open('py_output_header_parser.txt', 'w')
        self.f_entropy = open('py_output_entropy_decoder.txt', 'w')
        self.f_zigzag = open('py_output_zigzag.txt', 'w')
        self.f_dequant = open('py_output_dequant.txt', 'w')
        self.f_idct = open('py_output_idct.txt', 'w')
        self.f_mcu = open('py_output_mcu.txt', 'w')
        
        # Precompute IDCT Cosines
        self.C = np.zeros((8,8))
        for u in range(8):
            for x in range(8):
                self.C[u,x] = math.cos(((2*x + 1) * u * math.pi) / 16.0)

    def close_files(self):
        self.f_header.close()
        self.f_entropy.close()
        self.f_zigzag.close()
        self.f_dequant.close()
        self.f_idct.close()
        self.f_mcu.close()

    def parse(self):
        print("Parsing Header...")
        while self.pos < len(self.data):
             if self.data[self.pos] == 0xFF:
                 marker = self.data[self.pos+1]
                 self.pos += 2
                 if marker == 0xD8: # SOI
                     print("SOI Detected")
                 elif marker == 0xE0: # APP0
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.pos += length
                 elif marker == 0xDB: # DQT
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.parse_dqt(length)
                 elif marker == 0xC0: # SOF0
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.parse_sof0(length)
                 elif marker == 0xC4: # DHT
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.parse_dht(length)
                 elif marker == 0xDA: # SOS
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.parse_sos(length)
                     self.dump_header()
                     self.decode_scan()
                     break
                 elif marker == 0xD9: # EOI
                     break
                 else:
                     # Skip unknown
                     length = (self.data[self.pos] << 8) | self.data[self.pos+1]
                     self.pos += length
             else:
                 self.pos += 1

    def parse_dqt(self, length):
        end_pos = self.pos + length
        self.pos += 2 # Skip length
        while self.pos < end_pos:
            info = self.data[self.pos]
            self.pos += 1
            t_id = info & 0x0F
            table = []
            for _ in range(64):
                table.append(self.data[self.pos])
                self.pos += 1
            self.quant_tables[t_id] = table

    def parse_sof0(self, length):
        self.pos += 2 # Skip len
        self.pos += 1 # Precision
        self.img_height = (self.data[self.pos] << 8) | self.data[self.pos+1]
        self.pos += 2
        self.img_width = (self.data[self.pos] << 8) | self.data[self.pos+1]
        self.pos += 2
        self.num_components = self.data[self.pos]
        self.pos += 1
        for _ in range(self.num_components):
            c_id = self.data[self.pos]
            s = self.data[self.pos+1]
            q = self.data[self.pos+2]
            self.components.append({'id': c_id, 'h': s>>4, 'v': s&0x0F, 'q': q})
            self.pos += 3

    def parse_dht(self, length):
        end_pos = self.pos + length
        self.pos += 2
        while self.pos < end_pos:
            info = self.data[self.pos]
            self.pos += 1
            tc = info >> 4 # 0=DC, 1=AC
            th = info & 0x0F
            counts = []
            for _ in range(16):
                counts.append(self.data[self.pos])
                self.pos += 1
            symbols = []
            for c in counts:
                for _ in range(c):
                    symbols.append(self.data[self.pos])
                    self.pos += 1
            
            huff_map = {}
            code = 0
            for i, count in enumerate(counts):
                length_bits = i + 1
                for _ in range(count):
                    huff_map[ (length_bits, code) ] = symbols.pop(0)
                    code += 1
                code <<= 1
            
            table_type = 'DC' if tc == 0 else 'AC'
            self.huff_tables[table_type][th] = {'counts': counts, 'map': huff_map}

    def parse_sos(self, length):
        self.pos += length 
        
    def dump_header(self):
        self.f_header.write(f"Image Dimensions: {self.img_width}x{self.img_height}\n")
        self.f_header.write(f"Num Components: {self.num_components}\n")
        
        for qid in [0, 1]:
            if qid in self.quant_tables:
                name = "Luma" if qid == 0 else "Chroma"
                self.f_header.write(f"\nQuantization Table {qid} ({name}):\n")
                tbl = self.quant_tables[qid]
                for i, val in enumerate(tbl):
                    self.f_header.write(f"{val} ")
                    if (i+1) % 8 == 0: self.f_header.write("\n")
        
        if 0 in self.huff_tables['DC']:
             self.f_header.write("\nHuffman DC0 Counts:\n")
             for c in self.huff_tables['DC'][0]['counts']: self.f_header.write(f"{c} ")
        if 0 in self.huff_tables['AC']:
             self.f_header.write("\nHuffman AC0 Counts:\n")
             for c in self.huff_tables['AC'][0]['counts']: self.f_header.write(f"{c} ")
        if 1 in self.huff_tables['DC']:
             self.f_header.write("\nHuffman DC1 Counts:\n")
             for c in self.huff_tables['DC'][1]['counts']: self.f_header.write(f"{c} ")
        if 1 in self.huff_tables['AC']:
             self.f_header.write("\nHuffman AC1 Counts:\n")
             for c in self.huff_tables['AC'][1]['counts']: self.f_header.write(f"{c} ")
        self.f_header.write("\n")

    def get_huffman_symbol(self, bs, table_type, table_id):
        current_code = 0
        length = 0
        huff_map = self.huff_tables[table_type][table_id]['map']
        
        while length < 16:
            bit = bs.read_bit()
            current_code = (current_code << 1) | bit
            length += 1
            if (length, current_code) in huff_map:
                return huff_map[(length, current_code)]
        return 0

    def get_value(self, bs, size):
        if size == 0: return 0
        val = bs.read_bits(size)
        if val < (1 << (size - 1)):
            val = val - ((1 << size) - 1)
        return val

    def decode_scan(self):
        bs = BitStream(self.data[self.pos:]) 
        
        mcus_x = (self.img_width + 15) // 16
        mcus_y = (self.img_height + 15) // 16
        
        prev_dc = [0, 0, 0] 
        blk_idx = 0
        
        print("Decoding Scan Data...")
        
        for my in range(mcus_y):
            for mx in range(mcus_x):
                y_blocks = []
                for i in range(4):
                    blk, prev_dc[0] = self.decode_block(bs, 0, 0, prev_dc[0], blk_idx)
                    y_blocks.append(blk)
                    blk_idx += 1
                
                cb_blk, prev_dc[1] = self.decode_block(bs, 1, 1, prev_dc[1], blk_idx)
                blk_idx += 1
                
                cr_blk, prev_dc[2] = self.decode_block(bs, 1, 1, prev_dc[2], blk_idx)
                blk_idx += 1
                
                self.process_mcu(y_blocks, cb_blk, cr_blk, mx, my)

    def perform_idct(self, block):
        # Implement 2D IDCT manually S(x,y)
        # s(x,y) = 1/4 * sum(u=0..7) sum(v=0..7) C(u)C(v) S(u,v) cos(...) cos(...)
        # C(u) = 1/sqrt(2) if u=0 else 1.
        
        temp = np.zeros((8,8))
        for y in range(8): # For each row
            for x in range(8):
               sum_val = 0.0
               for u in range(8):
                   Cu = (1.0/math.sqrt(2)) if u==0 else 1.0
                   sum_val += Cu * block[y, u] * self.C[u, x]
               temp[y, x] = sum_val * 0.5

        # Col 1D IDCT on temp
        final = np.zeros((8,8))
        for x in range(8): # For each col
            for y in range(8):
                sum_val = 0.0
                for v in range(8):
                    Cv = (1.0/math.sqrt(2)) if v==0 else 1.0
                    sum_val += Cv * temp[v, x] * self.C[v, y]
                final[y, x] = sum_val * 0.5
                
        return final

    def decode_block(self, bs, dc_tbl_id, ac_tbl_id, prev_dc, blk_idx_count):
        # 1. Huffman
        size = self.get_huffman_symbol(bs, 'DC', dc_tbl_id)
        diff = self.get_value(bs, size)
        dc_val = prev_dc + diff
        
        # AC
        coeffs = [0]*64
        coeffs[0] = dc_val
        k = 1
        while k < 64:
            sym = self.get_huffman_symbol(bs, 'AC', ac_tbl_id)
            if sym == 0x00: break
            if sym == 0xF0: 
                k += 16
                continue
            
            run = sym >> 4
            size = sym & 0x0F
            val = self.get_value(bs, size)
            k += run
            if k < 64:
                coeffs[k] = val
                k += 1
        
        # Output Entropy/Zigzag
        self.f_entropy.write(f"Block {blk_idx_count}:\n")
        self.f_zigzag.write(f"Block {blk_idx_count}:\n")
        for i, v in enumerate(coeffs):
            self.f_entropy.write(f"{v} ")
            self.f_zigzag.write(f"{v} ")
            if (i+1)%8 == 0: 
                self.f_entropy.write("\n")
                self.f_zigzag.write("\n")
        self.f_entropy.write("\n")
        self.f_zigzag.write("\n")
        
        # 2. Dequant
        q_id = 0 if dc_tbl_id == 0 else 1
        q_tbl = self.quant_tables[q_id]
        dequant_coeffs = [0]*64
        for i in range(64):
            dequant_coeffs[i] = coeffs[i] * q_tbl[i]
            
        # Inverse Zigzag to Grid
        dct_grid = np.zeros((8,8))
        for i in range(64):
            # i is zigzag index
            natural_idx = ZIGZAG[i]
            r = natural_idx // 8
            c = natural_idx % 8
            dct_grid[r, c] = dequant_coeffs[i]
            
        self.f_dequant.write(f"Block {blk_idx_count}:\n")
        flat = dct_grid.flatten()
        for i, v in enumerate(flat):
            self.f_dequant.write(f"{int(v)} ")
            if (i+1)%8 == 0: self.f_dequant.write("\n")
        self.f_dequant.write("\n")
        
        # 3. IDCT
        idct_out = self.perform_idct(dct_grid)
        idct_out_int = np.round(idct_out).astype(int)
        
        self.f_idct.write(f"Block {blk_idx_count} (Input to MCU):\n")
        for i, val in enumerate(idct_out_int.flatten()):
            self.f_idct.write(f"{val} ")
            if (i+1)%8 == 0: self.f_idct.write("\n")
        self.f_idct.write("\n")
        
        return idct_out_int, dc_val

    def process_mcu(self, y_blocks, cb_blk, cr_blk, mx, my):
        Y_grid = np.zeros((16,16))
        Y_grid[0:8, 0:8] = y_blocks[0]
        Y_grid[0:8, 8:16] = y_blocks[1]
        Y_grid[8:16, 0:8] = y_blocks[2]
        Y_grid[8:16, 8:16] = y_blocks[3]
        
        Cb_grid = np.kron(cb_blk, np.ones((2,2)))
        Cr_grid = np.kron(cr_blk, np.ones((2,2)))
        
        for r in range(16):
            for c in range(16):
                px = mx*16 + c
                py = my*16 + r
                if px >= self.img_width or py >= self.img_height: continue
                
                y_val = Y_grid[r,c] + 128
                cb_val = Cb_grid[r,c]
                cr_val = Cr_grid[r,c]
                
                # Formula
                red = y_val + 1.402 * cr_val
                green = y_val - 0.344136 * cb_val - 0.714136 * cr_val
                blue = y_val + 1.772 * cb_val
                
                self.f_mcu.write(f"{int(clamp(red,0,255))} {int(clamp(green,0,255))} {int(clamp(blue,0,255))}\n")

if __name__ == "__main__":
    import os
    if not os.path.exists("test.hex"):
        print("Error: test.hex not found.")
    else:
        try:
            hex_data = read_hex_file("test.hex")
            decoder = JPEGDecoderModel(hex_data)
            decoder.parse()
            decoder.close_files()
            print("Done. Generated python output files.")
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
