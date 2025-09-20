# repair_group_definition.ps1
$path = "bible-scraper.py"
$lines = Get-Content $path

# Remove any old CATEGORY_GROUP definitions
$lines = $lines | Where-Object {$_ -notmatch 'CATEGORY_GROUP = "GROUP"'}

# Find index of CATEGORY_REQUIREMENTS
$idx = ($lines | Select-String 'CATEGORY_REQUIREMENTS:' | Select-Object -First 1).LineNumber - 1

$block = @'
# Clean: collective groups (Levites, Pharisees, Cretans, etc.)
CATEGORY_GROUP = "GROUP"
CATEGORY_BASE_WEIGHTS[CATEGORY_GROUP] = 3.4
if CATEGORY_GROUP not in CATEGORY_PRIORITY_ORDER:
    CATEGORY_PRIORITY_ORDER.insert(1, CATEGORY_GROUP)
if (CATEGORY_GROUP, 2) not in CATEGORY_REQUIREMENTS:
    CATEGORY_REQUIREMENTS.append((CATEGORY_GROUP, 2))

'@ -split "`r?`n"

# Insert block
$before = $lines[0..($idx-1)]
$after  = $lines[$idx..($lines.Count-1)]
$final  = $before + $block + $after

Set-Content $path $final -Encoding UTF8
Write-Host "✅ Inserted clean CATEGORY_GROUP block before CATEGORY_REQUIREMENTS (separate lines)"
