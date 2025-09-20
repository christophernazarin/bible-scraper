# fix_wldeh_403.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path $path)) { throw "bible-scraper.py not found" }

# backup
Copy-Item $path "${path}.bak_403_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force

$content = Get-Content $path -Raw

# (A) Ensure WldehCdnClient sets a User-Agent header once
$content = $content -replace '(class\s+WldehCdnClient:[\s\S]*?self\.session\s*=\s*requests\.Session\(\)\s*)',
'$0
        # Be polite to CDN: identify client
        try:
            self.session.headers.update({"User-Agent": "BibleScraper/1.0 (+https://example.local)"})
        except Exception:
            pass
'

# (B) Add gentle backoff + retry handling for 403 inside _fetch_per_verse
$content = $content -replace '(def\s+_fetch_per_verse\(self,\s*book:\s*BookMetadata,\s*chapter:\s*int\)\s*->\s*str:\s*\r?\n\s*verses:\s*List\[str\]\s*=\s*\[\]\s*\r?\n\s*verse\s*=\s*1\r?\n\s*while\s*verse\s*<=\s*200:\s*\r?\n\s*url\s*=\s*f".*?/verses/\{verse\}\.json"\s*\r?\n\s*response\s*=\s*self\.session\.get\(url,\s*timeout=REQUEST_TIMEOUT\)\s*\r?\n\s*if\s*response\.status_code\s*==\s*404:\s*\r?\n\s*break\s*\r?\n\s*if\s*response\.status_code\s*>=\s*400:\s*\r?\n\s*raise RuntimeError\(f"HTTP error \{response\.status_code\} for \{url\}"\)\s*\r?\n\s*try:\s*\r?\n\s*raw\s*=\s*response\.json\(\)\s*\r?\n\s*except json\.JSONDecodeError as exc:\s*\r?\n\s*raise RuntimeError\(f"Invalid verse JSON for \{url\}"\)\s*from exc\s*\r?\n\s*part\s*=\s*self\._coalesce_text\(raw\)\s*\r?\n\s*if\s*part:\s*\r?\n\s*verses\.append\(part\)\s*\r?\n\s*verse\s*\+=\s*1\s*\r?\n\s*return\s*"\s*"\.join\(verses\))',
@"
def _fetch_per_verse(self, book: BookMetadata, chapter: int) -> str:
        verses: List[str] = []
        verse = 1
        consecutive_403 = 0
        while verse <= 200:
            url = f"{self.base_url}/{self.version}/books/{book.slug}/chapters/{chapter}/verses/{verse}.json"
            response = self.session.get(url, timeout=REQUEST_TIMEOUT)
            # Normal end of chapter
            if response.status_code == 404:
                break
            # Gentle handling of rate limiting
            if response.status_code == 403:
                consecutive_403 += 1
                time.sleep(0.35)  # brief backoff
                if consecutive_403 >= 3:
                    # stop trying further verses; return what we have
                    break
                continue
            if response.status_code >= 400:
                raise RuntimeError(f"HTTP error {response.status_code} for {url}")
            try:
                raw = response.json()
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Invalid verse JSON for {url}") from exc
            part = self._coalesce_text(raw)
            if part:
                verses.append(part)
            # reset 403 counter on success; small pace delay to avoid rate limits
            consecutive_403 = 0
            time.sleep(0.12)
            verse += 1
        return " ".join(verses)
"@

Set-Content $path -Encoding UTF8 -Value $content
Write-Host "✅ Applied polite User-Agent + 403 backoff to WldehCdnClient"
