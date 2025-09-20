# fix_baseline_categories.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path -LiteralPath $path)) { Write-Error "bible-scraper.py not found."; exit 1 }

# 0) Backup
Copy-Item -LiteralPath $path -Destination "${path}.bak_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force

# 1) Load
$lines = Get-Content -LiteralPath $path

# 2) Hard purge all GROUP / group-clue detritus and broken labels
$purged = $lines | Where-Object {
    ($_ -notmatch 'CATEGORY_GROUP') -and
    ($_ -notmatch 'collective groups') -and
    ($_ -notmatch 'generate_group_clue') -and
    ($_ -notmatch 'Group identified as') -and
    ($_ -notmatch '^\s*CATEGORY_(BASE_WEIGHTS|PRIORITY_ORDER|REQUIREMENTS)\s*:\s*$') # stray "label:" lines
}

# 3) Identify category block: from first CATEGORY_PERSON to the line before TARGET_WORD_COUNT
$startMatch  = $purged | Select-String '^\s*CATEGOR(Y|Y_)?_?PERSON\s*=\s*"PERSON"' | Select-Object -First 1
$targetMatch = $purged | Select-String '^\s*TARGET_WORD_COUNT\s*=' | Select-Object -First 1

if (!$startMatch)  { Write-Error "Could not find start of category block (CATEGORY_PERSON = \"PERSON\")."; exit 1 }
if (!$targetMatch) { Write-Error "Could not find TARGET_WORD_COUNT anchor."; exit 1 }

$startIdx  = $startMatch.LineNumber - 1
$targetIdx = $targetMatch.LineNumber - 1
if ($startIdx -lt 0 -or $targetIdx -le $startIdx) { Write-Error "Invalid indices for category rewrite."; exit 1 }

$prefix = $purged[0..($startIdx-1)]
$suffix = $purged[$targetIdx..($purged.Count-1)]

# 4) Known-good category block (NO GROUP, exact syntax)
$block = @'
CATEGORY_PERSON = "PERSON"
CATEGORY_PLACE = "PLACE"
CATEGORY_OBJECT = "OBJECT"
CATEGORY_THEOLOGY = "THEOLOGY"
CATEGORY_OTHER = "OTHER"


CATEGORY_BASE_WEIGHTS: Dict[str, float] = {
    CATEGORY_OBJECT: 4.0,
    CATEGORY_PERSON: 3.6,
    CATEGORY_PLACE: 3.3,
    CATEGORY_THEOLOGY: 3.1,
    CATEGORY_OTHER: 1.4,
}

CATEGORY_PRIORITY_ORDER: List[str] = [
    CATEGORY_OBJECT,
    CATEGORY_PERSON,
    CATEGORY_PLACE,
    CATEGORY_THEOLOGY,
    CATEGORY_OTHER,
]

CATEGORY_REQUIREMENTS: List[Tuple[str, int]] = [
    (CATEGORY_OBJECT, 4),
    (CATEGORY_PERSON, 3),
    (CATEGORY_PLACE, 3),
    (CATEGORY_THEOLOGY, 3),
]
'@ -split "`r?`n"

# 5) Stitch
$final = @()
$final += $prefix
$final += $block
$final += $suffix

# 6) Write
Set-Content -LiteralPath $path -Value $final -Encoding UTF8

# 7) Sanity: ensure no leftover GROUP refs
$leftover = ($final | Select-String 'CATEGORY_GROUP|generate_group_clue|Group identified as|collective groups')
if ($leftover) {
  Write-Warning ("Removed most GROUP traces, but {0} leftover lines still reference it." -f $leftover.Count)
  $leftover | ForEach-Object { "  -> " + $_.Line }
} else {
  Write-Host "✅ Category block rebuilt and GROUP remnants purged."
}
