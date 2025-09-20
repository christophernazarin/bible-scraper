# apply_clue_fixes.ps1 (regex-based patcher)
$ErrorActionPreference = "Stop"
$path = ".\bible-scraper.py"
if (-not (Test-Path $path)) { throw "bible-scraper.py not found in current folder." }
$src  = Get-Content $path -Raw

# 1) Insert helpers after remove_answer_from_clue()
$patternRemoveAnswer = 'def remove_answer_from_clue\(clue: str, answer: str\):[\s\S]*?return cleaned\.strip\(",;:\. "\)\.strip\(\)\r?\n'

$helpers = @'

def _backfill_bare_function_words(text: str) -> str:
    if not text:
        return text
    patterns = [
        r"\b(of|in|at|to|from|for|with|by)\s*(?=[,.;:]|\Z)",
        r"\b(the|a|an)\s*(?=[,.;:]|\Z)",
        r"\b(of|in|at|to|from|for|with|by)\s+the\s*(?=[,.;:]|\Z)",
        r"\bthe\s+of\b",
    ]
    for pat in patterns:
        text = re.sub(pat, lambda m: m.group(0).rstrip() + " ___", text, flags=re.IGNORECASE)
    text = re.sub(r"\bthe\s+of\s+___\b", "the ___", text, flags=re.IGNORECASE)
    text = re.sub(r"(___)\s+(___)", r"\1", text)
    return text


def _normalize_grammar(text: str) -> str:
    if not text:
        return text
    t = text
    t = re.sub(r"\b[Nn]ow\b", "", t)
    t = re.sub(r"\s{2,}", " ", t)
    t = re.sub(r"\s+([,.;:])", r"\1", t)
    t = re.sub(r"([,.;:])([^\s])", r"\1 \2", t)
    t = re.sub(r"\bWe\s+sees\b", "We see", t)
    t = re.sub(r"\bWe\s+knows\b", "We know", t)
    t = re.sub(r"\bThey\s+sees\b", "They see", t)
    t = re.sub(r"\bThey\s+knows\b", "They know", t)
    t = re.sub(r"\b(\w+)\s+\1\b", r"\1", t, flags=re.IGNORECASE)
    t = re.sub(r"\b(the|a|an)\s+([,.;:])", r"\2", t, flags=re.IGNORECASE)
    t = _backfill_bare_function_words(t)
    t = re.sub(r"\s{2,}", " ", t).strip()
    return t


def _enforce_category_opening(category: str, body: str, *,
                              role_phrase: Optional[str] = None,
                              object_hypernym: str = "object") -> str:
    raw = body.strip()
    if category == CATEGORY_PERSON:
        lead = (role_phrase or "Figure")
        return f"{lead} who {raw}"
    if category == CATEGORY_PLACE:
        return "Place where " + re.sub(r"^\s*where\s+", "", raw, flags=re.IGNORECASE)
    if category == CATEGORY_OBJECT:
        if not re.match(r"^\s*this\b", raw, flags=re.IGNORECASE):
            raw = f"{object_hypernym} {raw}"
        return "This " + raw.lstrip()
    return raw

'@

$src = [regex]::Replace($src, $patternRemoveAnswer, { param($m) $m.Value + "`r`n" + $helpers }, 'Singleline')

# 2) extract_local_context: backfill before return
$patternContext = 'snippet = snippet\.strip\(" ,\.;:-"\)\r?\n\s*return snippet'
$replacementContext = "snippet = snippet.strip(`" ,.;:-`")`r`n    snippet = _backfill_bare_function_words(snippet)`r`n    return snippet"
$src = [regex]::Replace($src, $patternContext, $replacementContext, 'Singleline')

# 3) finalize_clue: replace body to call normalizers
$patternFinalize = 'def finalize_clue\(text: str\):\s*\r?\n\s*cleaned = re\.sub\(r"\\s\+", " ", text\)\.strip\(" ;,"\)\r?\n\s*if not cleaned:\s*\r?\n\s*return ""\s*\r?\n\s*if cleaned\[-1\] not in ".\?\!":\s*\r?\n\s*cleaned = f"{cleaned}\."\s*\r?\n\s*if cleaned and cleaned\[0\]\.islower\(\):\s*\r?\n\s*cleaned = cleaned\[0\]\.upper\(\) \+ cleaned\[1:\]\s*\r?\n\s*return truncate_text\(cleaned\)'
$finalizeBody = @'

def finalize_clue(text: str) -> str:
    repaired = _normalize_grammar(_backfill_bare_function_words(text))
    cleaned = re.sub(r"\s+", " ", repaired).strip(" ;,")
    if not cleaned:
        return ""
    if cleaned[-1] not in ".?!":
        cleaned = f"{cleaned}."
    if cleaned and cleaned[0].islower():
        cleaned = cleaned[0].upper() + cleaned[1:]
    return truncate_text(cleaned)

'@
$src = [regex]::Replace($src, $patternFinalize, $finalizeBody, 'Singleline')

# 4) PERSON: better role_phrase
$patternRole = 'role_phrase = role\.capitalize\(\) if role else "Figure"'
$replacementRole = 'role_phrase = (role.capitalize() if role and role.lower() not in {"man", "woman"} else "Figure")'
$src = [regex]::Replace($src, $patternRole, $replacementRole, 'Singleline')

# 5) PERSON: enforce opening
$patternPersonBuild = 'clue = f"{role_phrase} who {clue_body}"\s*\r?\n\s*clue = remove_answer_from_clue\(clue, candidate\.word\)'
$replacementPersonBuild = 'clue_raw = _enforce_category_opening(CATEGORY_PERSON, clue_body, role_phrase=role_phrase)
    clue = remove_answer_from_clue(clue_raw, candidate.word)'
$src = [regex]::Replace($src, $patternPersonBuild, $replacementPersonBuild, 'Singleline')

# 6) PLACE: “Place where …”
$patternPlace = 'if not description:\s*\r?\n\s*description = "is a location highlighted in this chapter"\s*\r?\n\s*clue = f"Where {description}"\s*\r?\n\s*clue = remove_answer_from_clue\(clue, candidate\.word\)'
$replacementPlace = 'if not description:
        description = "is a location highlighted in this chapter"
    clue_raw = _enforce_category_opening(CATEGORY_PLACE, description)
    clue = remove_answer_from_clue(clue_raw, candidate.word)'
$src = [regex]::Replace($src, $patternPlace, $replacementPlace, 'Singleline')

# 7) OBJECT: “This …”
$patternObject = 'if not description:\s*\r?\n\s*description = "object highlighted in this passage"\s*\r?\n\s*clue = remove_answer_from_clue\(description, candidate\.word\)\s*\r?\n\s*if clue and not clue\.lower\(\)\.startswith\(\("this", "these", "it", "symbol", "item"\)\):\s*\r?\n\s*clue = f"This {clue}" if not clue\.lower\(\)\.startswith\("this "\) else clue'
$replacementObject = 'if not description:
        description = "object highlighted in this passage"
    clue_raw = _enforce_category_opening(CATEGORY_OBJECT, description, object_hypernym="object")
    clue = remove_answer_from_clue(clue_raw, candidate.word)'
$src = [regex]::Replace($src, $patternObject, $replacementObject, 'Singleline')

# 8) Save & show diff
Set-Content -Path $path -Value $src -Encoding UTF8
git --no-pager diff -- .\bible-scraper.py
Write-Host "`nApplied clue fixes. Review the diff above, then commit:"
Write-Host "  git add -A"
Write-Host "  git commit -m `"Clue builder repairs (scripted)`""
