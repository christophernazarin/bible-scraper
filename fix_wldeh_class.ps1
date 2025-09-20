# fix_wldeh_class.ps1
$ErrorActionPreference = "Stop"
$path = "bible-scraper.py"
if (!(Test-Path $path)) { throw "bible-scraper.py not found" }

Copy-Item $path "${path}.bak_wldeh_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
$content = Get-Content $path -Raw

# Replace everything from 'class WldehCdnClient:' up to the *next* 'class ApiBibleClient:'
$pattern = '(?ms)^class\s+WldehCdnClient:[\s\S]*?^class\s+ApiBibleClient:'
$replacement = @"
class WldehCdnClient:
    def __init__(self, base_url: str, version: str, cache_dir: Path) -> None:
        self.base_url = base_url.rstrip("/")
        self.version = version.strip("/")
        self.cache_root = cache_dir / "wldeh" / self.version
        self.cache_root.mkdir(parents=True, exist_ok=True)
        self.session = requests.Session()
        # Be polite to CDN: identify client (and ignore if anything goes wrong)
        try:
            self.session.headers.update({"User-Agent": "BibleScraper/1.0 (+https://github.com/yourrepo)"})
        except Exception:
            pass

    @property
    def header_id(self) -> str:
        return f"wldeh:{self.version}"

    @property
    def source_label(self) -> str:
        return f"wldeh {self.version}"

    def fetch_book(self, book: BookMetadata, max_workers: int) -> List[ChapterPayload]:
        chapters = list(range(1, book.chapters + 1))
        payloads: List[ChapterPayload] = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_map = {executor.submit(self._load_chapter, book, chapter): chapter for chapter in chapters}
            for future in concurrent.futures.as_completed(future_map):
                payloads.append(future.result())
        payloads.sort(key=lambda item: item.chapter)
        return payloads

    def _cache_path(self, book: BookMetadata, chapter: int) -> Path:
        return self.cache_root / book.id / f"{book.id}.{chapter}.json"

    def _load_chapter(self, book: BookMetadata, chapter: int) -> ChapterPayload:
        cache_path = self._cache_path(book, chapter)
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        timing = ChapterTiming(book.id, chapter)
        if cache_path.exists():
            start = time.perf_counter()
            with cache_path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
            timing.fetch_seconds = time.perf_counter() - start
        else:
            start = time.perf_counter()
            payload = self._fetch_remote_chapter(book, chapter)
            with cache_path.open("w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False)
            timing.fetch_seconds = time.perf_counter() - start
        content = payload.get("data", {}).get("content", "")
        text = strip_markup(content)
        chapter_payload = ChapterPayload(
            book_id=book.id,
            book_name=book.name,
            chapter=chapter,
            chapter_id=f"{book.id}.{chapter}",
            text=text,
            timing=timing,
        )
        return chapter_payload

    def _fetch_remote_chapter(self, book: BookMetadata, chapter: int) -> Dict[str, Any]:
        url = f"{self.base_url}/{self.version}/books/{book.slug}/chapters/{chapter}.json"
        response = self.session.get(url, timeout=REQUEST_TIMEOUT)
        if response.status_code == 404:
            raise RuntimeError(f"Chapter not found: {book.id} {chapter}")
        if response.status_code >= 400:
            # Fall back to verse-by-verse on 4xx/5xx
            content = self._fetch_per_verse(book, chapter)
            return {"data": {"content": content}}
        try:
            raw = response.json()
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Invalid JSON for {url}") from exc
        content = self._coalesce_text(raw)
        if not content:
            content = self._fetch_per_verse(book, chapter)
        return {"data": {"content": content}}

    def _coalesce_text(self, data: Any) -> str:
        if isinstance(data, dict):
            if isinstance(data.get("text"), str):
                return strip_markup(data["text"])
            if isinstance(data.get("text"), list):
                return strip_markup(" ".join(str(part) for part in data["text"]))
            if isinstance(data.get("verses"), list):
                parts: List[str] = []
                for verse in data["verses"]:
                    if isinstance(verse, dict):
                        part = verse.get("text") or verse.get("content") or ""
                    else:
                        part = str(verse)
                    if part:
                        parts.append(part)
                return strip_markup(" ".join(parts))
            if isinstance(data.get("content"), str):
                return strip_markup(data["content"])
        if isinstance(data, list):
            return strip_markup(" ".join(str(item) for item in data))
        if isinstance(data, str):
            return strip_markup(data)
        return ""

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

class ApiBibleClient:
"@

if ($content -notmatch $pattern) {
    throw "Could not locate WldehCdnClient block to replace."
}

# Do the replacement and write back
$content = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Multiline)
Set-Content $path -Encoding UTF8 -Value $content
Write-Host "✅ Replaced WldehCdnClient with a clean, correctly indented version."
