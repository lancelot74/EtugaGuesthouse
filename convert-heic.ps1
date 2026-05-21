# convert-heic.ps1
# Converts HEIC/HEIF/JPG/PNG photos from source folders into the correct
# images/apartments/ destination folders, renamed gallery-1.jpg, gallery-2.jpg, etc.
#
# HOW TO RUN:
#   1. Right-click this file → "Run with PowerShell"
#      OR open PowerShell in this folder and type: .\convert-heic.ps1
#
#   2. If you get a permission error, run:
#      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
#      then try again.
#
# WHERE TO PUT YOUR SOURCE PHOTOS:
#   Place each apartment's folder of HEIC/photos inside the "images\" folder.
#   The folder must be named exactly as shown in the $mappings table below.
#   Example:  images\227\   ← put all photos for Apartment 227 here
#             images\228\   ← put all photos for Apartment 228 here
#             ... etc.
#
#   If your photos are in a different location (e.g. OneDrive), you can change
#   the $srcRoot variable at the top of this script to point there.
#
# REQUIREMENTS:
#   Windows must have the "HEIF Image Extensions" installed.
#   Install free from the Microsoft Store:
#   https://apps.microsoft.com/detail/9pmmsr1cgpwg
#
# NOTES:
#   - Existing gallery images in the destination are REPLACED (fresh renumber).
#   - The first image becomes both hero.jpg and thumb.jpg automatically.
#   - Folders that don't exist on disk are skipped with a warning.
#   - Images are resized to a max of 1920px wide and compressed at 82% quality.
#     Thumbnails (thumb.jpg) are resized to 800px wide at 75% quality.
#     Adjust $jpegQuality, $thumbQuality, and $maxWidth below if needed.

Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── SOURCE ROOT ──────────────────────────────────────────────────────────────
# By default, source folders live inside the project's "images\" folder.
# Change this line if your photos are elsewhere, e.g.:
#   $srcRoot = "C:\Users\YourName\OneDrive\Etuga Photos"
$srcRoot = Join-Path $scriptDir "images"

# ── DESTINATION ROOT ─────────────────────────────────────────────────────────
$dstRoot = Join-Path $scriptDir "images"

# ── COMPRESSION SETTINGS ─────────────────────────────────────────────────────
# JPEG quality for gallery images: 1 (tiny/bad) – 100 (huge/perfect). 82 = good balance.
$jpegQuality  = 82
# JPEG quality for thumb.jpg (shown in listing cards — smaller is fine).
$thumbQuality = 75
# Maximum pixel width for gallery/hero images. Larger images are scaled down.
# Phone HEIC photos are typically 4032px wide — this cuts them to ~25% of original size.
$maxWidth     = 1920
# Maximum pixel width for thumb.jpg.
$thumbMaxWidth = 800

# ── APARTMENT MAPPINGS ───────────────────────────────────────────────────────
# Format:  src = name of folder inside $srcRoot
#          dst = path inside $dstRoot where gallery images go
$mappings = @(
    @{ src = "227";          dst = "apartments\apt-01"; label = "Apartment 227"       },
    @{ src = "228";          dst = "apartments\apt-02"; label = "Apartment 228"       },
    @{ src = "2010";         dst = "apartments\apt-03"; label = "Apartment 2010"      },
    @{ src = "2011";         dst = "apartments\apt-04"; label = "Apartment 2011"      },
    @{ src = "38 toot - Comfy apartment"; dst = "apartments\apt-05"; label = "38 Toot" },
    @{ src = "4 Toot";       dst = "apartments\apt-06"; label = "4 Toot"              },
    @{ src = "Altai 61";     dst = "apartments\apt-07"; label = "Altai 61"            },
    @{ src = "Consul";       dst = "apartments\apt-08"; label = "Consul"              },
    @{ src = "Dulguun Nuur"; dst = "apartments\apt-09"; label = "Dulguun Nuur"        },
    @{ src = "Sunny Town II";dst = "apartments\apt-10"; label = "Sunny Town II"       }
)

# ── HELPERS ──────────────────────────────────────────────────────────────────

# Returns a System.Drawing.Imaging.EncoderParameters set to the given JPEG quality (0-100).
function Get-JpegEncoderParams {
    param([int]$Quality)
    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                 Where-Object { $_.MimeType -eq 'image/jpeg' } |
                 Select-Object -First 1
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality
    )
    return @{ Codec = $jpegCodec; Params = $encParams }
}

# Saves $img to $OutputPath as JPEG, resizing to at most $MaxPx wide (preserving aspect ratio).
function Save-ResizedJpeg {
    param(
        [System.Drawing.Image]$Image,
        [string]$OutputPath,
        [int]$MaxPx,
        [int]$Quality
    )
    $enc = Get-JpegEncoderParams -Quality $Quality

    if ($Image.Width -gt $MaxPx) {
        $ratio     = $MaxPx / $Image.Width
        $newWidth  = $MaxPx
        $newHeight = [int]($Image.Height * $ratio)
        $bmp = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($Image, 0, 0, $newWidth, $newHeight)
        $g.Dispose()
        $bmp.Save($OutputPath, $enc.Codec, $enc.Params)
        $bmp.Dispose()
    } else {
        $Image.Save($OutputPath, $enc.Codec, $enc.Params)
    }
}

function Convert-ImageToJpeg {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$MaxPx   = 1920,
        [int]$Quality = 82
    )
    $img = [System.Drawing.Image]::FromFile($InputPath)
    Save-ResizedJpeg -Image $img -OutputPath $OutputPath -MaxPx $MaxPx -Quality $Quality
    $img.Dispose()
}

# ── MAIN LOOP ────────────────────────────────────────────────────────────────
$totalConverted = 0
$totalSkipped   = 0

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Etuga Guesthouse — HEIC Converter    " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Source root : $srcRoot"
Write-Host "  Dest root   : $dstRoot"
Write-Host "  Gallery     : max $($maxWidth)px wide, quality $jpegQuality%"
Write-Host "  Thumbnails  : max $($thumbMaxWidth)px wide, quality $thumbQuality%"
Write-Host ""

foreach ($map in $mappings) {
    $srcDir = Join-Path $srcRoot $map.src
    $dstDir = Join-Path $dstRoot $map.dst

    if (-not (Test-Path $srcDir)) {
        Write-Host "SKIP  [$($map.label)]  — source folder not found: $srcDir" -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    # Collect all supported image files, sorted by name
    $files = Get-ChildItem -Path $srcDir -File |
             Where-Object { $_.Extension -imatch '\.(heic|heif|jpg|jpeg|png)$' } |
             Sort-Object Name

    if ($files.Count -eq 0) {
        Write-Host "WARN  [$($map.label)]  — no images found in $srcDir" -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    Write-Host "─────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "PROCESSING  [$($map.label)]  ($($files.Count) images)" -ForegroundColor Cyan
    Write-Host "  $srcDir  →  $dstDir" -ForegroundColor DarkGray

    # Ensure destination folder exists
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    $i = 1
    foreach ($file in $files) {
        $outPath = Join-Path $dstDir "gallery-$i.jpg"
        try {
            $sizeBefore = (Get-Item $file.FullName).Length
            Convert-ImageToJpeg -InputPath $file.FullName -OutputPath $outPath -MaxPx $maxWidth -Quality $jpegQuality
            $sizeAfter  = (Get-Item $outPath).Length
            $saving     = [math]::Round((1 - $sizeAfter / [math]::Max($sizeBefore,1)) * 100)
            Write-Host ("  [{0}/{1}]  {2}  →  gallery-{3}.jpg  ({4:N0} KB → {5:N0} KB, -{6}%)" -f `
                $i, $files.Count, $file.Name, $i,
                [math]::Round($sizeBefore/1KB), [math]::Round($sizeAfter/1KB), $saving) -ForegroundColor White
            $i++
            $totalConverted++
        } catch {
            Write-Host "  ERROR converting $($file.Name): $_" -ForegroundColor Red
        }
    }

    # First gallery image → hero.jpg (full size) and thumb.jpg (smaller, more compressed)
    $firstSrc = $files[0].FullName
    $heroPath  = Join-Path $dstDir "hero.jpg"
    $thumbPath = Join-Path $dstDir "thumb.jpg"
    try {
        $img = [System.Drawing.Image]::FromFile($firstSrc)
        Save-ResizedJpeg -Image $img -OutputPath $heroPath  -MaxPx $maxWidth      -Quality $jpegQuality
        Save-ResizedJpeg -Image $img -OutputPath $thumbPath -MaxPx $thumbMaxWidth  -Quality $thumbQuality
        $img.Dispose()
        $heroKB  = [math]::Round((Get-Item $heroPath).Length  / 1KB)
        $thumbKB = [math]::Round((Get-Item $thumbPath).Length / 1KB)
        Write-Host "  → hero.jpg ($heroKB KB)  |  thumb.jpg ($thumbKB KB)" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR creating hero/thumb: $_" -ForegroundColor Red
    }

    Write-Host "  ✓ Done — $($i - 1) images written to $($map.dst)" -ForegroundColor Green
}

# ── SUMMARY ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ("  Finished!  {0} images converted,  {1} folders skipped." -f $totalConverted, $totalSkipped) -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
