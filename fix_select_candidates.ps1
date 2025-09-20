# fix_select_candidates.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path $path)) { throw "bible-scraper.py not found" }

# backup
Copy-Item $path "${path}.bak_select_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force

$all   = Get-Content $path
$start = ($all | Select-String '^\s*def\s+select_candidates\(' | Select-Object -First 1).LineNumber
$end   = ($all | Select-String '^\s*def\s+infer_role\('        | Select-Object -First 1).LineNumber
if (!$start -or !$end) { throw "Could not find select_candidates(..) or infer_role(..)" }

$prefix = $all[0..($start-2)]
$suffix = $all[($end-1)..($all.Count-1)]

$block = @'
def select_candidates(candidates: List[Candidate]) -> List[Candidate]:
    if not candidates:
        return []
    ordered = sorted(candidates, key=lambda c: (-c.score, c.word))
    unique: List[Candidate] = []
    seen_words: Set[str] = set()
    seen_stems: Set[str] = set()
    seen_syns: Set[str] = set()
    for cand in ordered:
        if cand.word in seen_words:
            continue
        if cand.stem and cand.stem in seen_stems:
            continue
        duplicate = False
        for other in unique:
            if fuzz.ratio(cand.word, other.word) >= 85:
                duplicate = True
                break
        if duplicate:
            continue
        if cand.synset_lemmas and (cand.synset_lemmas & seen_syns):
            continue
        unique.append(cand)
        seen_words.add(cand.word)
        if cand.stem:
            seen_stems.add(cand.stem)
        if cand.synset_lemmas:
            seen_syns.update(cand.synset_lemmas)

    category_map: Dict[str, List[Candidate]] = defaultdict(list)
    for cand in unique:
        category_map[cand.category].append(cand)
    for cat_list in category_map.values():
        cat_list.sort(key=lambda c: (-c.score, c.word))

    final: List[Candidate] = []
    used_words: Set[str] = set()

    def take_candidate(c: Candidate) -> None:
        final.append(c)
        used_words.add(c.word)

    # Satisfy minimum per-category requirements
    for category, required in CATEGORY_REQUIREMENTS:
        cat_list = category_map.get(category, [])
        count = 0
        while cat_list and count < required and len(final) < MAX_WORD_COUNT:
            cand = cat_list.pop(0)
            if cand.word in used_words:
                continue
            take_candidate(cand)
            count += 1

    target = min(MAX_WORD_COUNT, max(MIN_WORD_COUNT, min(TARGET_WORD_COUNT, len(unique))))

    # Fill remaining by priority
    while len(final) < target:
        added = False
        for category in CATEGORY_PRIORITY_ORDER:
            cat_list = category_map.get(category, [])
            while cat_list:
                cand = cat_list.pop(0)
                if cand.word in used_words:
                    continue
                take_candidate(cand)
                added = True
                break
            if added and len(final) >= target:
                break
        if not added:
            break

    # If still short, take anything remaining (best-first)
    if len(final) < MIN_WORD_COUNT:
        for cat_list in category_map.values():
            while cat_list and len(final) < min(MAX_WORD_COUNT, len(unique)):
                cand = cat_list.pop(0)
                if cand.word in used_words:
                    continue
                take_candidate(cand)

    return final[:MAX_WORD_COUNT]
'@ -split "`r?`n"

$final = @()
$final += $prefix
$final += $block
$final += $suffix

Set-Content $path -Encoding UTF8 -Value $final
Write-Host "✅ Replaced select_candidates() with a clean version."
