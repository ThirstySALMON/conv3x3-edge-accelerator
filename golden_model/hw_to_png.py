import sys, os
import numpy as np
from PIL import Image

# input image next to what the RTL produced, from hex/image.hex and ../hw_out/<kernel>_out.hex
#   python hw_to_png.py sobel_x [sobel_y ...]   -> ../docs/edge_demo_<kernel>.png

IMG = 32
UP  = 6                      # 32 px is too small to look at, blow it up

def load_hex(path, bits):
    v = np.array([int(l, 16) for l in open(path) if l.strip()], dtype=np.int64)
    if bits == 16:
        v = np.where(v > 32767, v - 65536, v)     # two's complement
    return v.reshape(IMG, IMG)

def to_gray(a):
    a = a.astype(np.float64)
    a = (a - a.min()) / (a.max() - a.min() + 1e-9) * 255
    return Image.fromarray(a.astype(np.uint8)).resize((IMG*UP, IMG*UP), Image.NEAREST)

def main(kernels):
    here = os.path.dirname(os.path.abspath(__file__))
    img  = load_hex(os.path.join(here, "hex", "image.hex"), 8)
    outdir = os.path.join(here, "..", "docs")
    for k in kernels:
        hw = load_hex(os.path.join(here, "..", "hw_out", f"{k}_out.hex"), 16)
        a, b = to_gray(img), to_gray(hw)
        gap = 8
        canvas = Image.new("L", (a.width*2 + gap, a.height), 255)
        canvas.paste(a, (0, 0))
        canvas.paste(b, (a.width + gap, 0))
        out = os.path.join(outdir, f"edge_demo_{k}.png")
        canvas.save(out)
        print(f"{k}: hw range [{hw.min()}, {hw.max()}] -> {out}")

if __name__ == "__main__":
    main(sys.argv[1:] or ["sobel_x"])
