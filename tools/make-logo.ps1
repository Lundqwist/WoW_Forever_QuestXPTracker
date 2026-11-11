# Draws the "Qxp" badge used as the addon logo and minimap icon.
# Usage: .\tools\make-logo.ps1 -Size 512 -Png Media\logo.png
#        .\tools\make-logo.ps1 -Size 64  -Tga Media\QxpIcon.tga
param(
    [int]$Size = 512,
    [string]$Png,
    [string]$Tga
)
Add-Type -AssemblyName System.Drawing

$s = $Size / 64.0   # the design is laid out on a 64x64 grid
function Argb([int]$a, [int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function Rect([double]$x, [double]$y, [double]$w, [double]$h) { New-Object System.Drawing.RectangleF ([float]($x*$s)), ([float]($y*$s)), ([float]($w*$s)), ([float]($h*$s)) }

$bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.InterpolationMode = 'HighQualityBicubic'
$g.Clear([System.Drawing.Color]::Transparent)

# badge: dark purple disc with a soft top highlight
$disc = Rect 2 2 60 60
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $disc, (Argb 255 58 28 88), (Argb 255 12 6 22), 90
$g.FillEllipse($bg, $disc)
$shine = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Rect 8 4 48 26), (Argb 70 255 255 255), (Argb 0 255 255 255), 90
$g.FillEllipse($shine, (Rect 9 5 46 24))

# rings: outer purple, inner gold hairline
$ring = New-Object System.Drawing.Pen (Argb 255 150 80 220), ([float](3*$s))
$g.DrawEllipse($ring, (Rect 3 3 58 58))
$inner = New-Object System.Drawing.Pen (Argb 160 255 200 80), ([float](0.8*$s))
$g.DrawEllipse($inner, (Rect 6 6 52 52))

# lettering: big gold Q, green "xp" tucked into its lower right
$fam = New-Object System.Drawing.FontFamily "Georgia"
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$bold = [int][System.Drawing.FontStyle]::Bold
$q = New-Object System.Drawing.Drawing2D.GraphicsPath
$q.AddString("Q", $fam, $bold, [float](40*$s), (New-Object System.Drawing.PointF ([float](5*$s)), ([float](6*$s))), $fmt)
$xp = New-Object System.Drawing.Drawing2D.GraphicsPath
$xp.AddString("xp", $fam, $bold, [float](22*$s), (New-Object System.Drawing.PointF ([float](27*$s)), ([float](29*$s))), $fmt)

$outline = New-Object System.Drawing.Pen (Argb 255 0 0 0), ([float](5*$s))
$outline.LineJoin = 'Round'
$g.DrawPath($outline, $q)
$g.DrawPath($outline, $xp)

$gold = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Rect 0 5 64 56), (Argb 255 255 240 150), (Argb 255 225 140 15), 90
$g.FillPath($gold, $q)
$green = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Rect 0 29 64 34), (Argb 255 170 255 150), (Argb 255 25 185 45), 90
$g.FillPath($green, $xp)

# small sparkle top right (only drawn where it has room to read)
if ($Size -ge 128) {
    $spark = New-Object System.Drawing.SolidBrush (Argb 230 255 250 210)
    $cx = 49 * $s; $cy = 14 * $s; $l = 5 * $s; $w = 1.1 * $s
    $pts = @(
        (New-Object System.Drawing.PointF ([float]$cx), ([float]($cy - $l))),
        (New-Object System.Drawing.PointF ([float]($cx + $w)), ([float]($cy - $w))),
        (New-Object System.Drawing.PointF ([float]($cx + $l)), ([float]$cy)),
        (New-Object System.Drawing.PointF ([float]($cx + $w)), ([float]($cy + $w))),
        (New-Object System.Drawing.PointF ([float]$cx), ([float]($cy + $l))),
        (New-Object System.Drawing.PointF ([float]($cx - $w)), ([float]($cy + $w))),
        (New-Object System.Drawing.PointF ([float]($cx - $l)), ([float]$cy)),
        (New-Object System.Drawing.PointF ([float]($cx - $w)), ([float]($cy - $w)))
    )
    $g.FillPolygon($spark, [System.Drawing.PointF[]]$pts)
}
$g.Dispose()

if ($Png) {
    $bmp.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png)
    "wrote $Png"
}

if ($Tga) {
    # uncompressed 32-bit TGA, bottom-left origin (what WoW loads)
    $header = New-Object byte[] 18
    $header[2]  = 2
    $header[12] = $Size -band 0xFF; $header[13] = $Size -shr 8
    $header[14] = $Size -band 0xFF; $header[15] = $Size -shr 8
    $header[16] = 32
    $header[17] = 8
    $data = New-Object byte[] ($Size * $Size * 4)
    $i = 0
    for ($y = $Size - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $Size; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $data[$i] = $c.B; $data[$i+1] = $c.G; $data[$i+2] = $c.R; $data[$i+3] = $c.A
            $i += 4
        }
    }
    $bytes = New-Object byte[] (18 + $data.Length)
    [Array]::Copy($header, 0, $bytes, 0, 18)
    [Array]::Copy($data, 0, $bytes, 18, $data.Length)
    [System.IO.File]::WriteAllBytes($Tga, $bytes)
    "wrote $Tga"
}
$bmp.Dispose()
