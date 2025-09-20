# apply_group_patch.ps1
$path = "bible-scraper.py"
$src = Get-Content $path

# Find the line containing the last key of CATEGORY_BASE_WEIGHTS dict
$lineIndex = ($src | Select-String 'CATEGORY_OTHER: 1.4,' -List | Select-Object -First 1).LineNumber

if (-not $lineIndex) {
    Write-Host "❌ Could not find CATEGORY_OTHER inside CATEGORY_BASE_WEIGHTS"
    exit 1
}

# Insert block two lines after (so it’s after the closing brace "}")
$insertIndex = $lineIndex + 2

$groupBlock = @'
# New: collective groups (Levites, Pharisees, Cretans, etc.)
CATEGORY_GROUP = "GROUP"
CATEGORY_BASE_WEIGHTS[CATEGORY_GROUP] = 3.4
if CATEGORY_GROUP not in CATEGORY_PRIORITY_ORDER:
    CATEGORY_PRIORITY_ORDER.insert(1, CATEGORY_GROUP)
if (CATEGORY_GROUP, 2) not in CATEGORY_REQUIREMENTS:
    CATEGORY_REQUIREMENTS.append((CATEGORY_GROUP, 2))
'@

$newSrc = $src[0..($insertIndex-1)] + $groupBlock + $src[$insertIndex..($src.Count-1)]

# Write back
Set-Content $path $newSrc -Encoding UTF8
Write-Host "✅ CATEGORY_GROUP correctly inserted after CATEGORY_BASE_WEIGHTS"
