#!/usr/bin/env python3
"""Propose a folder-name -> site-id mapping for the photo import pipeline.

Given the catalog and a root of per-site photo folders, this prints a TSV the
owner can eyeball and paste into Tools/photo_manifest.tsv:

    <folder-name>\t<site-id>\t<confidence>\t<why / alternates>

Matching is deliberately conservative: it proposes a single site-id only when
it is confident, and flags everything else as AMBIGUOUS/UNMATCHED for a human
to resolve once (the manifest is then the permanent record — see
docs/CATALOG_AUTHORING.md and import_photos.sh).

Usage:
    python3 Tools/match_photo_folders.py <catalog.json> <photo-root>
"""
import json
import re
import sys
import unicodedata
from pathlib import Path


def norm(s: str) -> str:
    """Lowercase, strip accents/punctuation, collapse whitespace to spaces."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def tokens(s: str) -> set:
    return set(norm(s).split())


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit("usage: match_photo_folders.py <catalog.json> <photo-root>")
    catalog = json.loads(Path(sys.argv[1]).read_text())
    root = Path(sys.argv[2])

    cities = {c["id"]: c["name"] for c in catalog.get("cities", [])}
    sites = catalog["sites"]

    # Index sites by normalized name and normalized alternate name.
    by_name: dict[str, list] = {}
    for s in sites:
        keys = {norm(s["name"])}
        for a in s.get("alternateNames", []):
            keys.add(norm(a))
        for k in keys:
            by_name.setdefault(k, []).append(s)
    by_id = {s["id"]: s for s in sites}

    folders = sorted(
        (p for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")),
        key=lambda p: p.name.lower(),
    )

    print("# folder\tsite_id\tconfidence\tnote")
    for f in folders:
        fname = f.name
        fnorm = norm(fname)
        ftok = tokens(fname)
        proposal, conf, note = resolve(fname, fnorm, ftok, by_name, by_id, cities, sites)
        print(f"{fname}\t{proposal}\t{conf}\t{note}")
    return 0


def resolve(fname, fnorm, ftok, by_name, by_id, cities, sites):
    # 1) Direct slug: folder normalized to a hyphen-slug equals a site id.
    slug = fnorm.replace(" ", "-")
    if slug in by_id:
        return slug, "HIGH", "slug==id"

    # 2) Exact name/alternate match.
    cands = by_name.get(fnorm, [])
    if len(cands) == 1:
        return cands[0]["id"], "HIGH", "exact name"
    if len(cands) > 1:
        picked = disambiguate_by_city(ftok, cands, cities)
        if picked:
            return picked["id"], "HIGH", "exact name + city"
        ids = ",".join(c["id"] for c in cands)
        return "", "AMBIGUOUS", f"exact name, {len(cands)} sites: {ids}"

    # 3) City-prefixed folder: "Mystras Hagia Sophia" -> name "Hagia Sophia"
    #    in city "mystras". Try stripping a leading city word.
    for cid, cname in cities.items():
        cn = norm(cname)
        if cn and fnorm.startswith(cn + " "):
            rest = fnorm[len(cn) + 1 :]
            sub = by_name.get(rest, [])
            sub = [s for s in sub if s.get("cityId") == cid]
            if len(sub) == 1:
                return sub[0]["id"], "HIGH", f"city-prefix '{cname}' + name"

    # 4) Token-subset fallback: unique site whose name tokens are all present
    #    in the folder (or vice versa). Report as MEDIUM for human review.
    subset = []
    for s in sites:
        stok = tokens(s["name"])
        if stok and (stok <= ftok or ftok <= stok):
            subset.append(s)
    if len(subset) == 1:
        return subset[0]["id"], "MEDIUM", "token subset"
    if len(subset) > 1:
        ids = ",".join(s["id"] for s in subset[:6])
        return "", "AMBIGUOUS", f"{len(subset)} token candidates: {ids}"

    return "", "UNMATCHED", "no candidate"


def disambiguate_by_city(ftok, cands, cities):
    hits = []
    for c in cands:
        cid = c.get("cityId")
        cname = cities.get(cid, "")
        if cname and tokens(cname) & ftok:
            hits.append(c)
    return hits[0] if len(hits) == 1 else None


if __name__ == "__main__":
    raise SystemExit(main())
