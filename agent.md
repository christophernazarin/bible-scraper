# 📖 Bible-Scraper Agent

## 🔹 Mission
Bible-Scraper is an **AI-assisted clue generator** that processes Bible text into crossword-friendly word lists and contextual clues.  
The goal is to achieve **95% usable word–clue pairs** by combining:
- Linguistic parsing (SpaCy, NLTK, WordNet).
- Biblical/thematic knowledge integration.
- AI-driven enrichment for clarity, precision, and natural crossword style.

This work is done with excellence, stewardship, and reverence to God, ensuring resources are truthful and suitable for use in Christian education, worship, and general audiences.

---

## 🔹 Core Components

- **bible-scraper.py**  
  Main engine: fetches text, tokenizes, classifies words into categories (PERSON, PLACE, OBJECT, THEOLOGY, OTHER), scores and selects candidates, and generates clues.

- **Providers**  
  - `WldehCdnClient` → Fetches text from CDN JSON (default).
  - `ApiBibleClient` → Uses [api.scripture.api.bible](https://scripture.api.bible/) if API key provided.

- **Clue Generators**  
  - `generate_person_clue` → Uses roles, verb phrases, and hints.  
  - `generate_place_clue` → Context of location.  
  - `generate_object_clue` → Function/role in the sentence.  
  - `generate_theology_clue` → Abstract themes.  
  - `generate_generic_clue` → Fallback.  
  - **knowledge_enriched_clue** (new) → Incorporates external knowledge and thematic linking.

---

## 🔹 Goals of the Agent
- **Short-term**: Stabilize and repair code (cauterise broken pieces, remove duplication).  
- **Mid-term**: Improve classification and clue generation with knowledge enrichment.  
- **Long-term**: Reach 95% usable output across books/chapters, benchmarked against professional crossword standards.

---

## 🔹 Smoke Tests
Run a minimal check to confirm system integrity and clue quality:

```powershell
python -m py_compile .\bible-scraper.py
python .\bible-scraper.py --books 3JN,JUD --seed 7 --max-workers 1 --out out_smoke --cache .cache_smoke
notepad ".\out_smoke\3 John.txt"
notepad ".\out_smoke\Jude.txt"
```

✅ Pass = valid output file with ~15–20 words + readable clues.

---

## 🔹 Roadmap
1. **Stability / Cauterise**  
   - Ensure category/classify blocks are clean.  
   - Remove duplicate definitions.  
   - Validate helpers (`build_object_description`, etc.) exist before use.

2. **Clue Enrichment**  
   - Integrate broader knowledge base (general + biblical).  
   - Enforce crossword conventions (brevity, wit, variety).  
   - Contextual linking (“where…”, “who…”, “object used in…”).

3. **Selection Logic**  
   - Tune scoring to reduce noise words.  
   - Ensure balance across categories.  
   - Prioritize thematic relevance.

4. **Testing**  
   - Run across varied books (narrative, genealogy, letters, prophecy).  
   - Benchmark usability % against target.  
   - Continuous refinement.

---

## 🔹 Contributing
When making changes:
1. Always run **smoke test** before committing.  
2. Use **patches** (`.ps1` repair scripts or `.patch` diffs) for incremental, reversible edits.  
3. Aim for **minimal disruption** unless overhauling a broken mechanism.  
4. Keep comments in the code: `# CAUTERISE` for permanent fixes, `# TODO` for future refinement.

---

## 🔹 Guiding Principle
> *“And whatever you do, whether in word or deed, do it all in the name of the Lord Jesus…”* (Col. 3:17)

Excellence and clarity in this project serve both **education** and **worship**, making biblical engagement more interactive, accessible, and faithful.
