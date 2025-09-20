# fix_wldeh_indent.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path $path)) { throw "bible-scraper.py not found" }

Copy-Item $path "${path}.bak_indent_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
$content = Get-Content $path -Raw

# Ensure clean User-Agent block inside __init__
$content = $content -replace '(self\.session\s*=\s*requests\.Session\(\))',
'$1
        # Be polite to CDN: identify client
        try:
            self.session.headers.update({"User-Agent": "BibleScraper/1.0 (+https://example.local)"})
        except Exception:
            pass'

# Replace _fetch_per_verse with correctly indented version
$content = $content -replace 'def _fetch_per_verse\(.*?\):[\s\S]*?return " ".join\(verses\)',
@"
def _fetch_per_verse(self, book: BookMetadata, chapter: int) -> str:
        verses: List[str] = []
        verse = 1
        consecutive_403 = 0
        while verse <= 200:
            url = f"{self.base_url}/{self.version}/books/{book.slug}/chapters/{chapter}/verses/{verse}.json"
            response = self.session.get(url, timeout=REQUEST_TIMEOUT)
            if response.status_code == 404:
                break
            if response.status_code == 403:
                consecutive_403 += 1
                time.sleep(0.35)
                if consecutive_403 >= 3:
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
            consecutive_403 = 0
            time.sleep(0.12)
            verse += 1
        return " ".join(verses)
"@

Set-Content $path -Encoding UTF8 -Value $content
Write-Host "✅ Fixed indentation in _fetch_per_verse"
