# repair_classify_candidate.ps1
$path = "bible-scraper.py"
if (!(Test-Path -LiteralPath $path)) {
  Write-Error "bible-scraper.py not found."; exit 1
}

$all = Get-Content -LiteralPath $path

# Find function boundaries: from 'def classify_candidate(' up to the line before 'def compute_candidate_score('
$start = ($all | Select-String '^\s*def\s+classify_candidate\(' | Select-Object -First 1).LineNumber
$end   = ($all | Select-String '^\s*def\s+compute_candidate_score\(' | Select-Object -First 1).LineNumber

if (!$start -or !$end) { Write-Error "Could not locate function boundaries."; exit 1 }
$startIdx = $start - 1
$endIdx   = $end - 2  # inclusive end of classify_candidate block

$prefix = $all[0..($startIdx-1)]
$suffix = $all[($endIdx+1)..($all.Count-1)]

$cleanFunc = @'
def classify_candidate(token: Any, word: str, lemma: str) -> str:
    upper_word = normalize_upper(word)
    upper_lemma = normalize_upper(lemma)
    ent_type = token.ent_type_ if token is not None else ""
    if ent_type == "PERSON" or upper_word in KNOWN_PEOPLE or upper_lemma in KNOWN_PEOPLE:
        return CATEGORY_PERSON
    if ent_type in {"GPE", "LOC", "FAC"} or upper_word in KNOWN_PLACES:
        return CATEGORY_PLACE
    if upper_word in KNOWN_OBJECTS or upper_lemma in KNOWN_OBJECTS:
        return CATEGORY_OBJECT
    if upper_word in THEOLOGICAL_TERMS or upper_lemma in THEOLOGICAL_TERMS:
        return CATEGORY_THEOLOGY
    if token is None:
        return CATEGORY_OTHER
    if token.pos_ == "PROPN":
        if upper_word in KNOWN_PLACES:
            return CATEGORY_PLACE
        return CATEGORY_PERSON
    if token.pos_ == "NOUN":
        if upper_word in THEOLOGICAL_TERMS or upper_lemma in THEOLOGICAL_TERMS:
            return CATEGORY_THEOLOGY
        return CATEGORY_OBJECT
    if token.pos_ == "ADJ" and (upper_word in THEOLOGICAL_TERMS or upper_lemma in THEOLOGICAL_TERMS):
        return CATEGORY_THEOLOGY
    return CATEGORY_OTHER
'@ -split "`r?`n"

$final = @()
$final += $prefix
$final += $cleanFunc
$final += $suffix

Set-Content -LiteralPath $path -Value $final -Encoding UTF8
Write-Host "✅ Replaced classify_candidate with clean version."
