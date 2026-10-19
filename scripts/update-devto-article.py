#!/usr/bin/env python3
# CIDR Atlas
# Create or update the dev.to article from dev-to-article.md.
# Author: Sergio Farfan <sergio.farfan@gmail.com>
"""Publish dev-to-article.md to dev.to.

Usage:
    DEVTO_API_KEY=xxxx python3 scripts/update-devto-article.py --create [--publish]
    DEVTO_API_KEY=xxxx DEVTO_ARTICLE_ID=1234567 python3 scripts/update-devto-article.py

--create posts a new article with the title, tags and description below, as an
unpublished draft unless --publish is given; then record its article id in
ARTICLE_ID (or pass DEVTO_ARTICLE_ID). Without --create the
script updates the existing article's body only, so the title, tags, cover
image and description set in the editor are preserved.

The key comes from the environment only: never hardcode it, paste it into a
chat or commit it. Generate one at https://dev.to/settings/extensions and
revoke it there after use if in doubt. dev.to sits behind Cloudflare, which
rejects default Python user agents, hence the browser-like User-Agent.
"""

import json
import os
import sys
import urllib.error
import urllib.request

ARTICLE_ID = None  # Set after the first publication.
ARTICLE_SOURCE = os.path.join(os.path.dirname(__file__), "..", "dev-to-article.md")
TITLE = "CIDR Atlas: a local-first CIDR planner for OCI networks"
TAGS = "oci, flutter, dart, networking"  # comma-separated, up to four
DESCRIPTION = (
    "A macOS app and CLI that keep one local inventory of OCI VCN and subnet "
    "CIDRs, check overlaps per routing domain and recommend free space."
)


def request(method, url, payload, api_key):
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(payload).encode(),
        headers={
            "api-key": api_key,
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        },
    )
    try:
        with urllib.request.urlopen(req) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"HTTP {error.code}: {error.read().decode()[:500]}")


def main():
    api_key = os.environ.get("DEVTO_API_KEY")
    if not api_key:
        sys.exit("DEVTO_API_KEY is not set. See the usage at the top of this script.")
    with open(ARTICLE_SOURCE, encoding="utf-8") as source:
        body = source.read()

    if "--create" in sys.argv[1:]:
        result = request(
            "POST",
            "https://dev.to/api/articles",
            {
                "article": {
                    "title": TITLE,
                    "body_markdown": body,
                    "published": "--publish" in sys.argv[1:],
                    "tags": TAGS,
                    "description": DESCRIPTION,
                }
            },
            api_key,
        )
        state = "Published" if result.get("published") else "Draft created"
        print(f"{state}: id {result['id']} {result.get('url', '')}")
        return

    article_id = os.environ.get("DEVTO_ARTICLE_ID") or ARTICLE_ID
    if not article_id:
        sys.exit("No article id. Use --create first, then set ARTICLE_ID or DEVTO_ARTICLE_ID.")
    result = request(
        "PUT",
        f"https://dev.to/api/articles/{article_id}",
        {"article": {"body_markdown": body}},
        api_key,
    )
    print(f"Updated: {result['url']} (edited {result.get('edited_at', 'n/a')})")


if __name__ == "__main__":
    main()
