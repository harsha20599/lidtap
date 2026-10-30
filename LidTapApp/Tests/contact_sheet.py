"""Tiles test-artifact PNGs into contact sheets for quick visual review.  usage: contact_sheet.py OUT.png IMG...
"""
import sys
from PIL import Image, ImageDraw

out, files = sys.argv[1], sys.argv[2:]
thumbs = []
for f in files:
    im = Image.open(f).convert("RGB")
    im.thumbnail((700, 520))
    canvas = Image.new("RGB", (im.width, im.height + 22), (30, 30, 30))
    canvas.paste(im, (0, 22))
    ImageDraw.Draw(canvas).text((6, 5), f.rsplit("/", 1)[-1], fill=(220, 220, 220))
    thumbs.append(canvas)
cols = 2 if len(thumbs) > 1 else 1
rows = (len(thumbs) + cols - 1) // cols
w = max(t.width for t in thumbs); h = max(t.height for t in thumbs)
sheet = Image.new("RGB", (cols * w + (cols + 1) * 8, rows * h + (rows + 1) * 8), (15, 15, 15))
for i, t in enumerate(thumbs):
    sheet.paste(t, (8 + (i % cols) * (w + 8), 8 + (i // cols) * (h + 8)))
sheet.save(out)
