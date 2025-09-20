# cleanup_group_block.ps1
$path = "bible-scraper.py"
$lines = Get-Content $path

# Remove the stray CATEGORY_GROUP block between lines 190 and 200
$cleaned = @()
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($i -ge 189 -and $i -le 199) {
        if ($lines[$i] -match 'CATEGORY_GROUP|collective groups') {
            continue
        }
    }
    $cleaned += $lines[$i]
}

Set-Content $path $cleaned -Encoding UTF8
Write-Host "✅ Removed stray CATEGORY_GROUP block between lines 190–200"
