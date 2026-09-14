#!/usr/bin/env python3
"""
Pretty-print golden 3x3 windows as grids.

  python golden_model/view_windows.py impulse 528          # by window index
  python golden_model/view_windows.py impulse 16,16        # by (row, col)
  python golden_model/view_windows.py impulse 0-3          # index range
  python golden_model/view_windows.py hramp 0,0 -d         # decimal instead of hex
  python golden_model/view_windows.py ring 31,31 -s        # also show source pixels
  python golden_model/view_windows.py hramp all            # every window (all 1024)
  python golden_model/view_windows.py hramp all -c         # ...one compact line each
  python golden_model/view_windows.py hramp valid          # valid-conv interior only (30x30)

Window index n maps to output pixel (r, c) = (n // 32, n % 32), raster order.
Tap order per ARCHITECTURE_LOCKED S8:  tap[0..2]=a b c / tap[3..5]=d e f / tap[6..8]=g h i
"""
import sys, os

IMG_W = IMG_H = 32
VEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vectors")


def load(name):
    with open(os.path.join(VEC, name + "_windows_same.hex")) as f:
        wins = [[int(t, 16) for t in ln.split()] for ln in f if ln.strip()]
    with open(os.path.join(VEC, name + "_in.hex")) as f:
        src = [int(ln, 16) for ln in f if ln.strip()]
    return wins, src


def edges(r, c):
    e = [n for n, on in (("top", r == 0), ("bottom", r == IMG_H - 1),
                         ("left", c == 0), ("right", c == IMG_W - 1)) if on]
    return ", ".join(e) if e else "interior"


def compact(name, wins, n, dec):
    r, c = divmod(n, IMG_W)
    w = wins[n]
    fmt = (lambda v: "%3d" % v) if dec else (lambda v: "%02x" % v)
    rows = " | ".join(" ".join(fmt(w[3 * i + k]) for k in range(3)) for i in range(3))
    print("%4d (%2d,%2d)  %s  %s" % (n, r, c, rows, edges(r, c)))


def show(name, wins, src, n, dec, with_src):
    r, c = divmod(n, IMG_W)
    w = wins[n]
    fmt = (lambda v: "%3d" % v) if dec else (lambda v: "%02x" % v)

    print("%s  window %d   (r=%d, c=%d)   %s" % (name, n, r, c, edges(r, c)))
    for i in range(3):
        cells = [fmt(w[3 * i + k]) for k in range(3)]
        if i == 1:                      # mark the centre tap
            cells[1] = "[" + cells[1] + "]"
        else:
            cells[1] = " " + cells[1] + " "
        print("    " + " ".join(cells) + ("      <- taps %d-%d" % (3 * i, 3 * i + 2)))

    if with_src:
        print("    source pixels (0 = off-image, zero-padded):")
        for dy in (-1, 0, 1):
            row = []
            for dx in (-1, 0, 1):
                y, x = r + dy, c + dx
                row.append(".." if not (0 <= y < IMG_H and 0 <= x < IMG_W)
                           else fmt(src[y * IMG_W + x]))
            print("      " + " ".join(row))
    print()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    name, sel = sys.argv[1], sys.argv[2]
    dec = "-d" in sys.argv
    with_src = "-s" in sys.argv
    wins, src = load(name)

    if sel == "all":
        idx = range(IMG_W * IMG_H)
    elif sel in ("valid", "interior"):
        # 30x30 interior, no zero padding involved
        idx = [r * IMG_W + c for r in range(1, IMG_H - 1) for c in range(1, IMG_W - 1)]
    elif "," in sel:
        r, c = (int(x) for x in sel.split(","))
        idx = [r * IMG_W + c]
    elif "-" in sel:
        a, b = (int(x) for x in sel.split("-"))
        idx = range(a, b + 1)
    else:
        idx = [int(sel)]

    if "-c" in sys.argv:
        print("  win   (r, c)   taps 0-2   | taps 3-5   | taps 6-8    position")
        for n in idx:
            compact(name, wins, n, dec)
    else:
        for n in idx:
            show(name, wins, src, n, dec, with_src)
    return 0


if __name__ == "__main__":
    sys.exit(main())
