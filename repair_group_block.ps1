# repair_group_block.ps1
$path = "bible-scraper.py"
$src = Get-Content $path -Raw

# 1. Remove any existing CATEGORY_GROUP block (clean slate)
$src = $src -replace '(# New: collective groups[\s\S]+?CATEGORY_REQUIREMENTS.append\(.*?\)\n)', ''

# 2. Insert block after CATEGORY_BASE_WEIGHTS dictionary
$src = $src -replace '(CATEGORY_BASE_WEIGHTS:[\s\S]+?\})',
'$1

# New: collective groups (Levites, Pharisees, Cretans, etc.)
CATEGORY_GROUP = "GROUP"
CATEGORY_BASE_WEIGHTS[CATEGORY_GROUP] = 3.4
if CATEGORY_GROUP not in CATEGORY_PRIORITY_ORDER:
    CATEGORY_PRIORITY_ORDER.insert(1, CATEGORY_GROUP)
if (CATEGORY_GROUP, 2) not in CATEGORY_REQUIREMENTS:
    CATEGORY_REQUIREMENTS.append((CATEGORY_GROUP, 2))'

# Write back
Set-Content $path $src -Encoding UTF8
Write-Host "✅ CATEGORY_GROUP block rebuilt in the correct location"
