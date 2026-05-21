#!/usr/bin/env python3
"""
import_images.py
Extracts the OneDrive zip, converts HEIC → JPEG, resizes + compresses,
and writes gallery/hero/thumb images into the correct apartment folders.

Run from Ubuntu terminal:
    cd ~/projects/EtugaGuesthouse
    python3 import_images.py
"""

import os, sys, zipfile, tempfile, shutil
from pathlib import Path

# ── INSTALL DEPS IF MISSING ──────────────────────────────────────────────────
try:
    from PIL import Image
    import pillow_heif
except ImportError:
    print("Installing required packages...")
    os.system("pip3 install Pillow pillow-heif --break-system-packages -q")
    from PIL import Image
    import pillow_heif

pillow_heif.register_heif_opener()

# ── SETTINGS ─────────────────────────────────────────────────────────────────
ZIP_PATH       = Path("/mnt/c/Users/garhy/Downloads/OneDrive_2026-05-20.zip")
PROJECT_ROOT   = Path(__file__).parent
DST_ROOT       = PROJECT_ROOT / "images"

JPEG_QUALITY   = 82    # gallery + hero  (1–95, higher = bigger file)
THUMB_QUALITY  = 75    # thumb.jpg
MAX_WIDTH      = 1920  # gallery + hero max pixel width
THUMB_WIDTH    = 800   # thumb.jpg max pixel width

IMAGE_EXTS     = {".heic", ".heif", ".jpg", ".jpeg", ".png"}

# ── APARTMENT MAPPINGS ───────────────────────────────────────────────────────
MAPPINGS = [
    {"src": "ROM",          "dst": "guesthouses/gh-01", "label": "Guesthouse ROM (gh-01)"   },
    {"src": "URLAN",        "dst": "guesthouses/gh-02", "label": "Guesthouse URLAN (gh-02)" },
    {"src": "227",          "dst": "apartments/apt-01", "label": "Apartment 227"  },
    {"src": "228",          "dst": "apartments/apt-02", "label": "Apartment 228"  },
    {"src": "2010",         "dst": "apartments/apt-03", "label": "Apartment 2010" },
    {"src": "2011",         "dst": "apartments/apt-04", "label": "Apartment 2011" },
    {"src": "38 toot - Comfy apartment", "dst": "apartments/apt-05", "label": "38 Toot"},
    {"src": "4 Toot",       "dst": "apartments/apt-06", "label": "4 Toot"         },
    {"src": "Altai 61",     "dst": "apartments/apt-07", "label": "Altai 61"       },
    {"src": "Consul",       "dst": "apartments/apt-08", "label": "Consul"         },
    {"src": "Dulguun Nuur", "dst": "apartments/apt-09", "label": "Dulguun Nuur"   },
    {"src": "Sunny Town II","dst": "apartments/apt-10", "label": "Sunny Town II"  },
]

# ── HELPERS ──────────────────────────────────────────────────────────────────
def save_jpeg(img: Image.Image, path: Path, max_width: int, quality: int):
    """Resize to max_width (preserving aspect ratio) then save as JPEG."""
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    if img.width > max_width:
        ratio  = max_width / img.width
        new_h  = int(img.height * ratio)
        img    = img.resize((max_width, new_h), Image.LANCZOS)
    img.save(path, "JPEG", quality=quality, optimize=True)

def fmt_kb(path: Path) -> str:
    return f"{path.stat().st_size // 1024} KB"

# ── STEP 1: CHECK ZIP ────────────────────────────────────────────────────────
print()
print("=" * 45)
print("  Etuga Guesthouse — Image Importer")
print("=" * 45)

if not ZIP_PATH.exists():
    print(f"\n  ERROR: zip not found at {ZIP_PATH}")
    print("  Edit ZIP_PATH at the top of this script.")
    sys.exit(1)

print(f"  Zip  : {ZIP_PATH}")
print(f"  Dest : {DST_ROOT}")

# ── STEP 2: EXTRACT ──────────────────────────────────────────────────────────
tmp = Path(tempfile.mkdtemp(prefix="etuga_"))
print(f"\nExtracting zip to {tmp} ...")
with zipfile.ZipFile(ZIP_PATH, "r") as zf:
    zf.extractall(tmp)
print("  ✓ Extracted")

# ── STEP 3: FIND IMAGE FOLDERS ───────────────────────────────────────────────
# Collect all directories that directly contain image files
image_folders = {}
for folder in sorted(tmp.rglob("*")):
    if folder.is_dir():
        imgs = [f for f in folder.iterdir()
                if f.is_file() and f.suffix.lower() in IMAGE_EXTS]
        if imgs:
            image_folders[folder.name] = (folder, imgs)

print("\nFolders with images found in zip:")
for name, (folder, imgs) in image_folders.items():
    print(f"  {name}  ({len(imgs)} images)")

# ── STEP 4: CONVERT & COMPRESS ───────────────────────────────────────────────
converted = 0
skipped   = 0

for m in MAPPINGS:
    # Case-insensitive match
    match = next(
        ((folder, imgs) for name, (folder, imgs) in image_folders.items()
         if name.lower() == m["src"].lower()),
        None
    )

    if not match:
        print(f"\n  SKIP  [{m['label']}]  — no folder named '{m['src']}' in zip")
        skipped += 1
        continue

    src_folder, files = match
    files = sorted(files, key=lambda f: f.name)
    dst_dir = DST_ROOT / m["dst"]
    dst_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'─'*45}")
    print(f"  [{m['label']}]  {len(files)} images  →  {m['dst']}")

    for i, file in enumerate(files, start=1):
        out = dst_dir / f"gallery-{i}.jpg"
        try:
            size_before = file.stat().st_size // 1024
            img = Image.open(file)
            save_jpeg(img, out, MAX_WIDTH, JPEG_QUALITY)
            size_after  = out.stat().st_size // 1024
            saving      = round((1 - size_after / max(size_before, 1)) * 100)
            print(f"    [{i}/{len(files)}]  {file.name}  →  gallery-{i}.jpg"
                  f"  ({size_before} KB → {size_after} KB, -{saving}%)")
            converted += 1
        except Exception as e:
            print(f"    ERROR on {file.name}: {e}")

    # hero.jpg and thumb.jpg from the first image
    try:
        img = Image.open(files[0])
        hero_path  = dst_dir / "hero.jpg"
        thumb_path = dst_dir / "thumb.jpg"
        save_jpeg(img, hero_path,  MAX_WIDTH,   JPEG_QUALITY)
        save_jpeg(img, thumb_path, THUMB_WIDTH, THUMB_QUALITY)
        print(f"    → hero.jpg ({fmt_kb(hero_path)})  |  thumb.jpg ({fmt_kb(thumb_path)})")
    except Exception as e:
        print(f"    ERROR creating hero/thumb: {e}")

    print(f"  ✓ Done")

# ── STEP 5: CLEANUP ──────────────────────────────────────────────────────────
print("\nCleaning up temp files...")
shutil.rmtree(tmp)
print("  ✓ Done")

# ── SUMMARY ──────────────────────────────────────────────────────────────────
print()
print("=" * 45)
print(f"  Done!  {converted} images converted,  {skipped} folders skipped.")
print("=" * 45)
print()
