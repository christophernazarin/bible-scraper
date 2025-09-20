# fix_clue_block.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path -LiteralPath $path)) { Write-Error "bible-scraper.py not found."; exit 1 }

# Backup
Copy-Item -LiteralPath $path -Destination "${path}.bak_clue_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force

$all = Get-Content -LiteralPath $path

# Find block to replace
$start = ($all | Select-String '^\s*def\s+extract_verb_phrases\(' | Select-Object -First 1).LineNumber
$end   = ($all | Select-String '^\s*def\s+parse_books\('           | Select-Object -First 1).LineNumber

if (!$start -or !$end) { Write-Error "Could not locate block (extract_verb_phrases .. parse_books)."; exit 1 }
$startIdx = $start - 1
$endIdx   = $end - 2   # up to the line before def parse_books

$prefix = $all[0..($startIdx-1)]
$suffix = $all[($endIdx+1)..($all.Count-1)]

$block = @'
def extract_verb_phrases(token: Any, answer: str) -> List[str]:
    if token is None:
        return []
    phrases: List[str] = []
    answer_norm = normalize_upper(answer)
    for cand in token.sent:
        if cand.pos_ != "VERB":
            continue
        if not any(normalize_upper(node.text) == answer_norm for node in cand.subtree):
            continue
        base = third_person(cand.lemma_ if cand.lemma_ != "-PRON-" else cand.text)
        if not base:
            continue
        fragments: List[str] = []
        for child in sorted(cand.children, key=lambda t: t.i):
            if child.dep_ in {"dobj", "pobj", "prep", "advmod", "prt", "attr", "acomp", "obl", "oprd"}:
                words = [t.text for t in sorted(child.subtree, key=lambda t: t.i)]
                fragment = " ".join(words)
                if answer.lower() in fragment.lower():
                    continue
                fragments.append(fragment)
        clause = base
        if fragments:
            clause = f"{base} {' '.join(fragments[:2])}"
        clause = sanitize_clause(clause)
        clause = remove_answer_from_clue(clause, answer)
        if not clause:
            continue
        if clause not in phrases:
            phrases.append(clause)
        if len(phrases) == 3:
            break
    return phrases


def generate_person_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    doc = payload.doc
    token = doc[candidate.token_index] if doc is not None and 0 <= candidate.token_index < len(doc) else None
    context_words: Set[str] = set()
    if token is not None:
        for word in token.sent:
            norm = processor.normalize_token(word.text)
            if norm:
                context_words.add(norm)
    role = infer_role(candidate.word, context_words, payload.vocab)
    role_phrase = (role.capitalize() if role and role.lower() not in {"man", "woman"} else "Figure")
    verb_phrases = candidate.context_phrases or (extract_verb_phrases(token, candidate.word) if token else [])
    hints = extract_hint_phrases(context_words)
    clue_body = ""
    if verb_phrases:
        clue_body = verb_phrases[0]
        if hints and hints[0] not in clue_body:
            clue_body = f"{clue_body}, {hints[0]}"
    else:
        summary = summarize_context(token, candidate.word, CATEGORY_PERSON)
        if summary:
            clue_body = summary
    if not clue_body:
        clue_body = "plays a key role in this chapter"
    clue_raw = _enforce_category_opening(CATEGORY_PERSON, clue_body, role_phrase=role_phrase)
    clue = remove_answer_from_clue(clue_raw, candidate.word)
    clue = finalize_clue(clue)
    return ensure_unique_structure(clue, token, candidate, existing_signatures)


def build_place_description(token: Any, answer: str) -> str:
    if token is None:
        return ""
    governing = None
    preposition = None
    if token.dep_ == "pobj" and token.head.pos_ == "ADP":
        preposition = token.head
        governing = preposition.head
    elif token.dep_ in {"nsubj", "nsubjpass"}:
        governing = token.head
    else:
        for ancestor in token.ancestors:
            if ancestor.pos_ == "VERB":
                governing = ancestor
                break
    if governing is None:
        return ""
    subject = get_subject_phrase(governing, answer)
    verb_phrase = build_verb_phrase(governing, answer)
    if not verb_phrase:
        verb_phrase = third_person(governing.lemma_ if governing.lemma_ != "-PRON-" else governing.text)
    prep_text = preposition.text.lower() if preposition is not None else "at"
    if subject:
        return f"{subject} {verb_phrase} {prep_text} this place"
    return f"{verb_phrase.capitalize()} {prep_text} this place"


def generate_place_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    doc = payload.doc
    token = doc[candidate.token_index] if doc is not None and 0 <= candidate.token_index < len(doc) else None
    description = build_place_description(token, candidate.word)
    if not description:
        summary = summarize_context(token, candidate.word, CATEGORY_PLACE)
        if summary:
            description = summary
    if not description:
        description = "is a location highlighted in this chapter"
    clue_raw = _enforce_category_opening(CATEGORY_PLACE, description)
    clue = remove_answer_from_clue(clue_raw, candidate.word)
    clue = finalize_clue(clue)
    return ensure_unique_structure(clue, token, candidate, existing_signatures)


def build_object_description(token: Any, answer: str) -> str:
    if token is None:
        return ""
    verb = None
    preposition = None
    if token.dep_ in {"dobj", "obj"}:
        verb = token.head
    elif token.dep_ == "pobj" and token.head.pos_ == "ADP":
        preposition = token.head
        verb = preposition.head
    elif token.dep_ == "attr":
        verb = token.head
    else:
        for ancestor in token.ancestors:
            if ancestor.pos_ == "VERB":
                verb = ancestor
                break
    if verb is None:
        return ""
    subject = get_subject_phrase(verb, answer)
    verb_phrase = build_verb_phrase(verb, answer)
    if preposition is not None and subject:
        return f"{subject} {verb_phrase} {preposition.text.lower()} this"
    if subject and verb_phrase:
        return f"{subject} {verb_phrase} this"
    if verb_phrase:
        return f"{verb_phrase.capitalize()} this"
    return ""


def generate_object_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    doc = payload.doc
    token = doc[candidate.token_index] if doc is not None and 0 <= candidate.token_index < len(doc) else None
    description = build_object_description(token, candidate.word)
    if not description:
        summary = summarize_context(token, candidate.word, CATEGORY_OBJECT)
        if summary:
            description = summary
    if not description:
        description = "object highlighted in this passage"
    clue_raw = _enforce_category_opening(CATEGORY_OBJECT, description, object_hypernym="object")
    clue = remove_answer_from_clue(clue_raw, candidate.word)
    clue = finalize_clue(clue)
    return ensure_unique_structure(clue, token, candidate, existing_signatures)


def build_theology_description(token: Any, answer: str) -> str:
    if token is None:
        return ""
    verb = None
    if token.dep_ in {"pobj", "dobj", "obj", "attr", "acomp", "oprd"}:
        head = token.head
        if head is not None and head.pos_ == "VERB":
            verb = head
    if verb is None and token.dep_ == "ROOT" and token.pos_ == "VERB":
        verb = token
    if verb is not None:
        subject = get_subject_phrase(verb, answer)
        verb_phrase = build_verb_phrase(verb, answer)
        if subject and verb_phrase:
            return f"{subject} {verb_phrase}"
        if verb_phrase:
            return f"{verb_phrase.capitalize()}"
    if token.dep_ == "attr" and token.head.pos_ == "VERB":
        subject = get_subject_phrase(token.head, answer)
        verb_phrase = build_verb_phrase(token.head, answer)
        if subject and verb_phrase:
            return f"{subject} {verb_phrase}"
    for child in token.children:
        if child.dep_ == "relcl":
            fragment = format_subtree_tokens(child.subtree, answer)
            if fragment:
                return fragment
    return ""


def generate_theology_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    doc = payload.doc
    token = doc[candidate.token_index] if doc is not None and 0 <= candidate.token_index < len(doc) else None
    description = build_theology_description(token, candidate.word)
    if not description:
        summary = summarize_context(token, candidate.word, CATEGORY_THEOLOGY)
        if summary:
            description = summary
    if not description:
        description = "key theme in this chapter"
    clue = f"Concept {description}"
    clue = remove_answer_from_clue(clue, candidate.word)
    clue = finalize_clue(clue)
    return ensure_unique_structure(clue, token, candidate, existing_signatures)


def generate_generic_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    doc = payload.doc
    token = doc[candidate.token_index] if doc is not None and 0 <= candidate.token_index < len(doc) else None
    summary = summarize_context(token, candidate.word, CATEGORY_OTHER)
    if not summary:
        summary = "mentioned in this chapter"
    clue = remove_answer_from_clue(summary, candidate.word)
    clue = finalize_clue(clue)
    return ensure_unique_structure(clue, token, candidate, existing_signatures)


def generate_clue(
    candidate: Candidate,
    processor: TextProcessor,
    payload: ChapterPayload,
    existing_signatures: Set[str],
) -> str:
    if candidate.category == CATEGORY_PERSON:
        return generate_person_clue(candidate, processor, payload, existing_signatures)
    if candidate.category == CATEGORY_PLACE:
        return generate_place_clue(candidate, processor, payload, existing_signatures)
    if candidate.category == CATEGORY_OBJECT:
        return generate_object_clue(candidate, processor, payload, existing_signatures)
    if candidate.category == CATEGORY_THEOLOGY:
        return generate_theology_clue(candidate, processor, payload, existing_signatures)
    return generate_generic_clue(candidate, processor, payload, existing_signatures)
'@ -split "`r?`n"

$final = @()
$final += $prefix
$final += $block
# Keep def parse_books and everything after it
$final += $suffix

Set-Content -LiteralPath $path -Encoding UTF8 -Value $final
Write-Host "✅ Replaced clue-generation block with a clean, known-good version."
