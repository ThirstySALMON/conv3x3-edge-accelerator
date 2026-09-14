import numpy as np
import os

IMG = 32
HEX_DIR = "hex"
PNG_DIR = "png"
KERNELS = {
    "identity":  [[0,0,0],[0,1,0],[0,0,0]],
    "sobel_x":   [[-1,0,1],[-2,0,2],[-1,0,1]],
    "sobel_y":   [[-1,-2,-1],[0,0,0],[1,2,1]],
    "sharpen":   [[0,-1,0],[-1,5,-1],[0,-1,0]],
    "laplacian": [[0,1,0],[1,-4,1],[0,1,0]],
    # not real filters, just push the accumulator past +/-32767 to hit the saturation paths
    "satmax":    [[127,127,127],[127,127,127],[127,127,127]],
    "satmin":    [[-128,-128,-128],[-128,-128,-128],[-128,-128,-128]],
}

def conv(img, k, relu=False):
    k = np.array(k, dtype=np.int32)
    out = np.zeros((IMG, IMG), dtype=np.int32)
    for y in range(IMG):
        for x in range(IMG):
            acc = 0
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    iy, ix = y+dy, x+dx
                    if 0 <= iy < IMG and 0 <= ix < IMG:
                        acc += int(img[iy,ix]) * int(k[dy+1,dx+1])
            acc = max(-32768, min(32767, acc))
            if relu and acc < 0:
                acc = 0
            out[y,x] = acc
    return out

def load_image(path):
    if path.endswith(".hex"):   # reuse an existing image.hex so outputs stay in sync
        v = [int(l, 16) for l in open(path) if l.strip()]
        return np.array(v, dtype=np.uint8).reshape(IMG, IMG)
    from PIL import Image
    im = Image.open(path).convert("L").resize((IMG, IMG))
    return np.array(im, dtype=np.uint8)

def save_png(arr, path):
    from PIL import Image
    a = arr.astype(np.float64)
    a = (a - a.min()) / (a.max() - a.min() + 1e-9) * 255
    Image.fromarray(a.astype(np.uint8)).resize((256,256), Image.NEAREST).save(path)

def run(img):
    os.makedirs(HEX_DIR, exist_ok=True)
    os.makedirs(PNG_DIR, exist_ok=True)
    np.savetxt(f"{HEX_DIR}/image.hex", img.reshape(-1), fmt="%02x")
    save_png(img, f"{PNG_DIR}/image.png")
    for name, k in KERNELS.items():
        # coefficients in write_addr order (row-major), two's complement
        with open(f"{HEX_DIR}/{name}_coef.hex", "w") as f:
            for row in k:
                for c in row:
                    f.write(f"{c & 0xff:02x}\n")
        out = conv(img, k)
        with open(f"{HEX_DIR}/{name}_out.hex", "w") as f:
            for v in out.reshape(-1):
                f.write(f"{int(v) & 0xffff:04x}\n")
        relu = conv(img, k, relu=True)
        with open(f"{HEX_DIR}/{name}_relu_out.hex", "w") as f:
            for v in relu.reshape(-1):
                f.write(f"{int(v) & 0xffff:04x}\n")
        save_png(out, f"{PNG_DIR}/{name}.png")
        print(f"{name}: acc range [{out.min()}, {out.max()}]")
    print(f"wrote {HEX_DIR}/ and {PNG_DIR}/")

if __name__ == "__main__":
    import sys
    # python golden.py cat.png        new image
    # python golden.py hex/image.hex  regenerate outputs for the image already in hex/
    if len(sys.argv) > 1:
        img = load_image(sys.argv[1])
    else:
        img = np.random.default_rng(0).integers(0, 256, (IMG, IMG), dtype=np.uint8)
    run(img)