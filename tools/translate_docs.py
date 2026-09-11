#!/usr/bin/env python3
"""
Translation script for qbe.mbt documentation.

Translates Chinese documentation files from doc/zh/ to English in doc/.
Supports multiple LLM providers (OpenAI, DeepL, Anthropic, etc.).

Usage:
    python tools/translate_docs.py --provider openai --api-key YOUR_KEY
    python tools/translate_docs.py --provider deepl --api-key YOUR_KEY
    python tools/translate_docs.py --file doc/zh/types.md  # translate single file
    python tools/translate_docs.py --incremental  # only translate changed files

Environment Variables:
    OPENAI_API_KEY    - OpenAI API key
    DEEPL_API_KEY     - DeepL API key
    ANTHROPIC_API_KEY - Anthropic API key
"""

import os
import sys
import json
import hashlib
import argparse
from pathlib import Path
from typing import Optional, Dict, List, Tuple
from dataclasses import dataclass
from datetime import datetime


@dataclass
class TranslationConfig:
    provider: str  # openai, deepl, anthropic, mock
    api_key: str
    model: str
    api_base: Optional[str] = None
    temperature: float = 0.3
    max_retries: int = 3


class TranslationProvider:
    """Base class for translation providers."""

    def translate(self, text: str, source_lang: str = "zh", target_lang: str = "en") -> str:
        raise NotImplementedError


class MockProvider(TranslationProvider):
    """Mock provider for testing without API calls."""

    def translate(self, text: str, source_lang: str = "zh", target_lang: str = "en") -> str:
        # Simple mock: add "[EN]" prefix to each line
        lines = text.split("\n")
        return "\n".join(f"[EN] {line}" for line in lines)


class OpenAIProvider(TranslationProvider):
    """OpenAI API translation provider."""

    def __init__(self, config: TranslationConfig):
        self.config = config
        try:
            import openai
            self.client = openai.OpenAI(
                api_key=config.api_key,
                base_url=config.api_base or "https://api.openai.com/v1"
            )
        except ImportError:
            raise ImportError("openai package not installed. Run: pip install openai")

    def translate(self, text: str, source_lang: str = "zh", target_lang: str = "en") -> str:
        system_prompt = f"""You are a professional technical translator specializing in compiler and programming language documentation.
Translate the following Markdown documentation from {source_lang} to {target_lang}.

Rules:
1. Preserve all Markdown formatting (headings, code blocks, links, tables)
2. Keep code blocks, inline code, and file paths unchanged
3. Translate comments inside code blocks if they are in the source language
4. Keep technical terms that are commonly used in English (SSA, CFG, ABI, etc.)
5. Maintain the same level of technical precision
6. Do not add or remove any content"""

        user_prompt = f"Translate the following Markdown documentation from {source_lang} to {target_lang}:\n\n{text}"

        response = self.client.chat.completions.create(
            model=self.config.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=self.config.temperature,
        )
        return response.choices[0].message.content


class DeepLProvider(TranslationProvider):
    """DeepL API translation provider."""

    def __init__(self, config: TranslationConfig):
        self.config = config
        try:
            import requests
            self.requests = requests
        except ImportError:
            raise ImportError("requests package not installed. Run: pip install requests")
        self.base_url = config.api_base or "https://api-free.deepl.com/v2"

    def translate(self, text: str, source_lang: str = "zh", target_lang: str = "en") -> str:
        # Map language codes
        lang_map = {"zh": "ZH", "en": "EN"}
        source = lang_map.get(source_lang, source_lang.upper())
        target = lang_map.get(target_lang, target_lang.upper())

        response = self.requests.post(
            f"{self.base_url}/translate",
            data={
                "auth_key": self.config.api_key,
                "text": text,
                "source_lang": source,
                "target_lang": target,
            }
        )
        response.raise_for_status()
        return response.json()["translations"][0]["text"]


class AnthropicProvider(TranslationProvider):
    """Anthropic API translation provider."""

    def __init__(self, config: TranslationConfig):
        self.config = config
        try:
            import anthropic
            self.client = anthropic.Anthropic(api_key=config.api_key)
        except ImportError:
            raise ImportError("anthropic package not installed. Run: pip install anthropic")

    def translate(self, text: str, source_lang: str = "zh", target_lang: str = "en") -> str:
        system_prompt = f"""You are a professional technical translator specializing in compiler and programming language documentation.
Translate the following Markdown documentation from {source_lang} to {target_lang}.

Rules:
1. Preserve all Markdown formatting (headings, code blocks, links, tables)
2. Keep code blocks, inline code, and file paths unchanged
3. Translate comments inside code blocks if they are in the source language
4. Keep technical terms that are commonly used in English (SSA, CFG, ABI, etc.)
5. Maintain the same level of technical precision
6. Do not add or remove any content"""

        message = self.client.messages.create(
            model=self.config.model,
            max_tokens=8192,
            system=system_prompt,
            messages=[
                {"role": "user", "content": f"Translate the following Markdown documentation from {source_lang} to {target_lang}:\n\n{text}"}
            ],
            temperature=self.config.temperature,
        )
        return message.content[0].text


def get_provider(config: TranslationConfig) -> TranslationProvider:
    """Get translation provider based on config."""
    providers = {
        "mock": MockProvider,
        "openai": OpenAIProvider,
        "deepl": DeepLProvider,
        "anthropic": AnthropicProvider,
    }
    provider_class = providers.get(config.provider)
    if not provider_class:
        raise ValueError(f"Unknown provider: {config.provider}. Supported: {list(providers.keys())}")
    return provider_class(config)


class DocumentationTranslator:
    """Handles translation of documentation files."""

    def __init__(self, config: TranslationConfig, source_dir: Path, target_dir: Path):
        self.config = config
        self.source_dir = source_dir
        self.target_dir = target_dir
        self.provider = get_provider(config)
        self.hash_file = target_dir / ".translation_hashes.json"
        self.hashes = self._load_hashes()

    def _load_hashes(self) -> Dict[str, str]:
        """Load file hashes for incremental translation."""
        if self.hash_file.exists():
            with open(self.hash_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {}

    def _save_hashes(self) -> None:
        """Save file hashes for incremental translation."""
        with open(self.hash_file, "w", encoding="utf-8") as f:
            json.dump(self.hashes, f, indent=2, ensure_ascii=False)

    def _compute_hash(self, content: str) -> str:
        """Compute hash of file content."""
        return hashlib.md5(content.encode("utf-8")).hexdigest()

    def _needs_translation(self, source_path: Path, target_path: Path) -> bool:
        """Check if file needs translation."""
        if not target_path.exists():
            return True
        if not source_path.exists():
            return False

        source_content = source_path.read_text(encoding="utf-8")
        source_hash = self._compute_hash(source_content)

        if str(source_path) in self.hashes:
            return self.hashes[str(source_path)] != source_hash
        return True

    def translate_file(self, source_path: Path, target_path: Path, force: bool = False) -> bool:
        """Translate a single file. Returns True if translation was performed."""
        if not force and not self._needs_translation(source_path, target_path):
            print(f"  Skipped (unchanged): {source_path.name}")
            return False

        print(f"  Translating: {source_path.name}...")
        source_content = source_path.read_text(encoding="utf-8")

        try:
            translated = self.provider.translate(source_content)
            target_path.parent.mkdir(parents=True, exist_ok=True)
            target_path.write_text(translated, encoding="utf-8")
            self.hashes[str(source_path)] = self._compute_hash(source_content)
            print(f"  Done: {target_path.name}")
            return True
        except Exception as e:
            print(f"  Error translating {source_path.name}: {e}")
            return False

    def translate_directory(self, force: bool = False) -> Tuple[int, int]:
        """Translate all files in source directory. Returns (translated, skipped)."""
        translated = 0
        skipped = 0

        if not self.source_dir.exists():
            print(f"Source directory not found: {self.source_dir}")
            return 0, 0

        source_files = list(self.source_dir.glob("*.md"))
        print(f"Found {len(source_files)} source files in {self.source_dir}")

        for source_path in sorted(source_files):
            target_path = self.target_dir / source_path.name
            if self.translate_file(source_path, target_path, force):
                translated += 1
            else:
                skipped += 1

        self._save_hashes()
        return translated, skipped

    def translate_file_list(self, files: List[str], force: bool = False) -> Tuple[int, int]:
        """Translate specific files. Returns (translated, skipped)."""
        translated = 0
        skipped = 0

        for filename in files:
            source_path = self.source_dir / filename
            target_path = self.target_dir / filename
            if self.translate_file(source_path, target_path, force):
                translated += 1
            else:
                skipped += 1

        self._save_hashes()
        return translated, skipped


def create_lang_links(doc_dir: Path) -> None:
    """Add language navigation links to all English docs."""
    doc_dir = Path(doc_dir)
    zh_dir = doc_dir / "zh"

    if not doc_dir.exists() or not zh_dir.exists():
        print("doc/ or doc/zh/ not found")
        return

    for md_file in doc_dir.glob("*.md"):
        if md_file.name == "README.md":
            continue  # Handle README separately

        content = md_file.read_text(encoding="utf-8")
        zh_file = zh_dir / md_file.name

        if zh_file.exists():
            # Add Chinese link at the top if not present
            if "[中文版本" not in content:
                # Find the first heading and add link after it
                lines = content.split("\n")
                insert_pos = 0
                for i, line in enumerate(lines):
                    if line.startswith("#"):
                        insert_pos = i + 1
                        break

                link = f"\n[中文版本 (Chinese Version)](zh/{md_file.name})\n"
                lines.insert(insert_pos, link)
                md_file.write_text("\n".join(lines), encoding="utf-8")
                print(f"  Added language link: {md_file.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Translate qbe.mbt documentation from Chinese to English"
    )
    parser.add_argument(
        "--provider",
        choices=["openai", "deepl", "anthropic", "mock"],
        default="mock",
        help="Translation provider (default: mock)"
    )
    parser.add_argument(
        "--api-key",
        help="API key for translation provider"
    )
    parser.add_argument(
        "--model",
        help="Model name (for OpenAI/Anthropic)"
    )
    parser.add_argument(
        "--api-base",
        help="Custom API base URL"
    )
    parser.add_argument(
        "--file",
        help="Translate specific file (relative to doc/zh/)"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force retranslation of all files"
    )
    parser.add_argument(
        "--incremental",
        action="store_true",
        help="Only translate changed files (default)"
    )
    parser.add_argument(
        "--add-links",
        action="store_true",
        help="Add language navigation links to existing docs"
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("doc/zh"),
        help="Source directory with Chinese docs (default: doc/zh)"
    )
    parser.add_argument(
        "--target-dir",
        type=Path,
        default=Path("doc"),
        help="Target directory for English docs (default: doc)"
    )

    args = parser.parse_args()

    # Handle add-links mode
    if args.add_links:
        create_lang_links(args.target_dir)
        return

    # Get API key from environment if not provided
    api_key = args.api_key
    if not api_key:
        env_var_map = {
            "openai": "OPENAI_API_KEY",
            "deepl": "DEEPL_API_KEY",
            "anthropic": "ANTHROPIC_API_KEY",
        }
        env_var = env_var_map.get(args.provider)
        if env_var:
            api_key = os.getenv(env_var)
        if not api_key and args.provider != "mock":
            print(f"Error: API key required for {args.provider} provider")
            print(f"Set {env_var} environment variable or use --api-key")
            sys.exit(1)

    # Get model from environment or use default
    model = args.model
    if not model:
        if args.provider == "openai":
            model = os.getenv("OPENAI_MODEL", "gpt-4o")
        elif args.provider == "anthropic":
            model = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")

    # Create config
    config = TranslationConfig(
        provider=args.provider,
        api_key=api_key or "",
        model=model or "",
        api_base=args.api_base,
    )

    # Create translator
    translator = DocumentationTranslator(
        config=config,
        source_dir=args.source_dir,
        target_dir=args.target_dir,
    )

    print(f"Translation provider: {args.provider}")
    print(f"Source directory: {args.source_dir}")
    print(f"Target directory: {args.target_dir}")
    print()

    # Translate
    if args.file:
        files = [args.file] if not args.file.endswith("*") else [
            f.name for f in args.source_dir.glob(args.file)
        ]
        translated, skipped = translator.translate_file_list(files, force=args.force)
    else:
        translated, skipped = translator.translate_directory(force=args.force)

    print()
    print(f"Translation complete: {translated} translated, {skipped} skipped")


if __name__ == "__main__":
    main()
