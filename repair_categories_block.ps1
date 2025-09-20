# repair_categories_block.ps1
$path = "bible-scraper.py"
if (!(Test-Path -LiteralPath $path)) {
  Write-Error "bible-scraper.py not found in current folder."; exit 1
}

# Load once
$lines = Get-Content -LiteralPath $path

# Find the category block boundaries:
# start = first occurrence of 'CATEGORY_PERSON = "PERSON"'
# end   = the line where 'TARGET_WORD_COUNT =' begins (we keep it and everything after)
$startMatch  = $lines | Select-String '^CATEGORY_PERSON\s*=\s*"PERSON"' | Select-Object -First 1
$targetMatch = $lines | Select-String '^\s*TARGET_WORD_COUNT\s*='       | Select-Object -First 1

if (!$startMatch)  { Write-Error "Could not find start of category block (CATEGORY_PERSON)."; exit 1 }
if (!$targetMatch) { Write-Error "Could not find end anchor (TARGET_WORD_COUNT)."; exit 1 }

$startIdx  = $startMatch.LineNumber - 1
$targetIdx = $targetMatch.LineNumber - 1

if ($startIdx -le 0 -or $targetIdx -le $startIdx) {
  Write-Error "Invalid indices for rewrite: start=$startIdx target=$targetIdx"; exit 1
}

# Prefix (everything before categories) and suffix (from TARGET_WORD_COUNT onward)
$prefix = $lines[0..($startIdx-1)]
$suffix = $lines[$targetIdx..($lines.Count-1)]

# Canonical, clean category block (no GROUP)
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

# Write back
$final = @()
$final += $prefix
$final += $block
$final += $suffix

Set-Content -LiteralPath $path -Value $final -Encoding UTF8
Write-Host "✅ Rewrote category block to a clean, known-good state."

# Quick sanity: ensure no leftover GROUP references
$groupRefs = ($final | Select-String 'CATEGORY_GROUP').Count
if ($groupRefs -gt 0) {
  Write-Warning "Found $groupRefs references to CATEGORY_GROUP elsewhere in file. They may need removal."
}

# Optional: print the rewritten block lines
$catStart = ((Get-Content -LiteralPath $path) | Select-String '^CATEGORY_PERSON\s*=' -List).LineNumber
$catEnd   = ((Get-Content -LiteralPath $path) | Select-String '^\s*TARGET_WORD_COUNT\s*=' -List).LineNumber - 1
"{0}..{1} (rewritten)" -f $catStart, $catEnd | Write-Host
