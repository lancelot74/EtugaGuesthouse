# import-from-zip.ps1
# Extracts your OneDrive photo zip, maps each folder to the correct apartment,
# converts HEIC → JPEG, resizes, compresses, and writes gallery/hero/thumb images.
#
# HOW TO RUN:
#   1. Right-click this file → "Run with PowerShell"
#      OR open PowerShell in this folder and type: .\import-from-zip.ps1
#
#   2. If you get a permission error, run:
#      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
#      then try again.
#
# REQUIREMENTS:
#   Windows "HEIF Image Extensions" must be installed (free from Microsoft Store):
#   https://apps.microsoft.com/detail/9pmmsr1cgpwg

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── SETTINGS ─────────────────────────────────────────────────────────────────
# Path to your zip file
$zipPath = "C:\Users\garhy\Downloads\OneDrive_2026-05-20.zip"

# Where the website images live
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dstRoot   = Join-Path $scriptDir "images"

# Temp folder where the zip is extracted (deleted at the end)
$tempDir   = Join-Path $env:TEMP "EtugaImport_$(Get-Random)"

# JPEG quality: 1 (tiny/ugly) – 100 (huge/perfect)
$jpegQuality   = 82   # gallery + hero images
$thumbQuality  = 75   # thumb.jpg (listing card)

# Max pixel width
$maxWidth      = 1920  # gallery + hero
$thumbMaxWidth = 800   # thumb.jpg

# ── APARTMENT MAPPINGS ───────────────────────────────────────────────────────
# "src" = folder name inside the zip (case-insensitive match)
# "dst" = destination under images\apartments\
$mappings = @(
    @{ src = "227";          dst = "apartments\apt-01"; label = "Apartment 227"  },
    @{ src = "228";          dst = "apartments\apt-02"; label = "Apartment 228"  },
    @{ src = "2010";         dst = "apartments\apt-03"; label = "Apartment 2010" },
    @{ src = "2011";         dst = "apartments\apt-04"; label = "Apartment 2011" },
    @{ src = "38 Toot";      dst = "apartments\apt-05"; label = "38 Toot"        },
    @{ src = "4 Toot";       dst = "apartments\apt-06"; label = "4 Toot"         },
    @{ src = "Altai 61";     dst = "apartments\apt-07"; label = "Altai 61"       },
    @{ src = "Consul";       dst = "apartments\apt-08"; label = "Consul"         },
    @{ src = "Dulguun Nuur"; dst = "apartments\apt-09"; label = "Dulguun Nuur"   },
    @{ src = "Sunny Town II";dst = "apartments\apt-10"; label = "Sunny Town II"  }
)

# ── HELPERS ──────────────────────────────────────────────────────────────────
function Get-JpegEncoder {
    [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq 'image/jpeg' } |
        Select-Object -First 1
}

function New-EncoderParams([int]$Quality) {
    $p = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
    $p
}

function Save-ResizedJpeg {
    param([System.Drawing.Image]$Image, [string]$OutputPath, [int]$MaxPx, [int]$Quality)
    $codec  = Get-JpegEncoder
    $params = New-EncoderParams $Quality
    if ($Image.Width -gt $MaxPx) {
        $ratio = $MaxPx / $Image.Width
        $w = $MaxPx; $h = [int]($Image.Height * $ratio)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($Image, 0, 0, $w, $h)
        $g.Dispose()
        $bmp.Save($OutputPath, $codec, $params)
        $bmp.Dispose()
    } else {
        $Image.Save($OutputPath, $codec, $params)
    }
}

# ── STEP 1: VERIFY ZIP ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Etuga Guesthouse — ZIP Importer      " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

if (-not (Test-Path $zipPath)) {
    Write-Host ""
    Write-Host "ERROR: zip file not found at:" -ForegroundColor Red
    Write-Host "  $zipPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Edit the `$zipPath variable at the top of this script and try again." -ForegroundColor Yellow
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "  Zip  : $zipPath"
Write-Host "  Dest : $dstRoot"
Write-Host "  Temp : $tempDir"
Write-Host ""

# ── STEP 2: EXTRACT ──────────────────────────────────────────────────────────
Write-Host "Extracting zip..." -ForegroundColor Cyan
try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempDir)
    Write-Host "  ✓ Extracted to $tempDir" -ForegroundColor Green
} catch {
    Write-Host "  ERROR extracting zip: $_" -ForegroundColor Red
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# ── STEP 3: SHOW WHAT'S IN THE ZIP ──────────────────────────────────────────
$topFolders = Get-ChildItem -Path $tempDir -Directory -Recurse |
              Where-Object {
                  # Only folders that directly contain image files
                  (Get-ChildItem $_.FullName -File |
                   Where-Object { $_.Extension -imatch '\.(heic|heif|jpg|jpeg|png)$' }).Count -gt 0
              }

Write-Host ""
Write-Host "Folders with images found in zip:" -ForegroundColor Cyan
foreach ($f in $topFolders) {
    $imgCount = (Get-ChildItem $f.FullName -File |
                 Where-Object { $_.Extension -imatch '\.(heic|heif|jpg|jpeg|png)$' }).Count
    Write-Host "  $($f.Name)  ($imgCount images)" -ForegroundColor White
}
Write-Host ""

# ── STEP 4: CONVERT & COMPRESS ───────────────────────────────────────────────
$totalConverted = 0
$totalSkipped   = 0

foreach ($map in $mappings) {
    # Find matching folder (case-insensitive, also search subdirectories)
    $srcDir = $topFolders | Where-Object { $_.Name -ieq $map.src } | Select-Object -First 1

    if (-not $srcDir) {
        Write-Host "SKIP  [$($map.label)]  — no matching folder '$($map.src)' found in zip" -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    $files = Get-ChildItem -Path $srcDir.FullName -File |
             Where-Object { $_.Extension -imatch '\.(heic|heif|jpg|jpeg|png)$' } |
             Sort-Object Name

    if ($files.Count -eq 0) {
        Write-Host "WARN  [$($map.label)]  — folder found but no images inside" -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    $dstDir = Join-Path $dstRoot $map.dst
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    Write-Host "─────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "PROCESSING  [$($map.label)]  ($($files.Count) images)" -ForegroundColor Cyan

    $i = 1
    foreach ($file in $files) {
        $outPath = Join-Path $dstDir "gallery-$i.jpg"
        try {
            $sizeBefore = $file.Length
            $img = [System.Drawing.Image]::FromFile($file.FullName)
            Save-ResizedJpeg -Image $img -OutputPath $outPath -MaxPx $maxWidth -Quality $jpegQuality
            $img.Dispose()
            $sizeAfter = (Get-Item $outPath).Length
            $saving    = [math]::Round((1 - $sizeAfter / [math]::Max($sizeBefore,1)) * 100)
            Write-Host ("  [{0}/{1}]  {2}  →  gallery-{3}.jpg  ({4:N0} KB → {5:N0} KB, -{6}%)" -f `
                $i, $files.Count, $file.Name, $i,
                [math]::Round($sizeBefore/1KB), [math]::Round($sizeAfter/1KB), $saving) -ForegroundColor White
            $i++
            $totalConverted++
        } catch {
            Write-Host "  ERROR on $($file.Name): $_" -ForegroundColor Red
        }
    }

    # hero.jpg and thumb.jpg from the first image
    try {
        $img = [System.Drawing.Image]::FromFile($files[0].FullName)
        $heroPath  = Join-Path $dstDir "hero.jpg"
        $thumbPath = Join-Path $dstDir "thumb.jpg"
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

# ── STEP 5: CLEAN UP TEMP ────────────────────────────────────────────────────
Write-Host ""
Write-Host "Cleaning up temp files..." -ForegroundColor DarkGray
Remove-Item -Recurse -Force $tempDir
Write-Host "  ✓ Temp folder deleted" -ForegroundColor DarkGray

# ── SUMMARY ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ("  Done!  {0} images converted,  {1} folders skipped." -f $totalConverted, $totalSkipped) -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
