# full_cleanup_group.ps1
$path = "bible-scraper.py"
$lines = Get-Content $path

$cleaned = @()
$insideBadBlock = $false
$clueSeen = $false

foreach ($line in $lines) {
    # --- Remove CATEGORY_GROUP blocks before CATEGORY_OTHER ---
    if ($line -match 'CATEGORY_GROUP = "GROUP"') {
        $lineIndex = [array]::IndexOf($lines, $line)
        $beforeOther = ($lines[0..$lineIndex] | Select-String 'CATEGORY_OTHER = "OTHER"')
        if (-not $beforeOther) {
            # skip this block
            $insideBadBlock = $true
            continue
        }
    }

    if ($insideBadBlock) {
        if ($line -match 'CATEGORY_REQUIREMENTS.append') {
            $insideBadBlock = $false
        }
        continue
    }

    # --- Remove duplicate generate_clue inserts ---
    if ($line -match 'if candidate.category == CATEGORY_GROUP') {
        if ($clueSeen -eq $true) {
            continue
        } else {
            $clueSeen = $true
        }
    }

    $cleaned += $line
}

Set-Content $path $cleaned -Encoding UTF8
Write-Host "Cleaned: kept only CATEGORY_GROUP after CATEGORY_BASE_WEIGHTS"
