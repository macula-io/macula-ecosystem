#!/usr/bin/env python3
"""Generate FEATURES.md: what Macula does today, built only from released, checkable sources.

This exists so anyone can read one current technical document of Macula that cannot claim
more than is built (macula-ecosystem#1).

Sources, and nothing else:
  1. Components: the highest released semver tag of each repository in features/sources.json
     (a public image registry for components whose source is private).
  2. Capabilities: the README section between `<!-- features:start -->` and
     `<!-- features:end -->` at that released tag. Every bullet must name, in backticks, at
     least one path that exists at that tag; a bullet that does not is refused.
  3. Security: data/security_register.json, the public (TLP:CLEAR) export of the security
     register, delivered by the register's own CI. Quoted exactly; refused unless its
     evaluator verdict is green on the same register sha.

The output is refused if it matches any pattern in FEATURES_DENYLIST (newline-separated,
case-insensitive regular expressions, held as a secret so the list itself is never public).

Usage:
  generate_features.py [--out FEATURES.md] [--check]
Environment: GH_TOKEN (optional, raises the GitHub API rate limit), FEATURES_DENYLIST (required).
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "features", "sources.json")
REGISTER = os.path.join(ROOT, "data", "security_register.json")

MARK_START = "<!-- features:start -->"
MARK_END = "<!-- features:end -->"
SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
BACKTICK = re.compile(r"`([^`\s]+)`")


class Refused(Exception):
    """The generator will not write a document that could claim more than is built."""


# ---------------------------------------------------------------- fetching

def _get(url, accept="application/vnd.github+json", token=None):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "macula-features"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


class GitHub:
    """The few reads the generator needs; a fake with the same methods drives the tests."""

    def __init__(self, token=None):
        self.token = token

    def tags(self, repo):
        names, page = [], 1
        while True:
            body = _get(f"https://api.github.com/repos/{repo}/tags?per_page=100&page={page}",
                        token=self.token)
            batch = json.loads(body)
            names += [(t["name"], t["commit"]["sha"]) for t in batch]
            if len(batch) < 100:
                return names
            page += 1

    def readme(self, repo, ref):
        try:
            return _get(f"https://raw.githubusercontent.com/{repo}/{ref}/README.md",
                        accept="text/plain").decode("utf-8")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise

    def path_exists(self, repo, ref, path):
        url = (f"https://api.github.com/repos/{repo}/contents/"
               f"{urllib.parse.quote(path)}?ref={urllib.parse.quote(ref)}")
        try:
            _get(url, token=self.token)
            return True
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return False
            raise

    def image_tags(self, image):
        # Anonymous pull token: works only for a public package, which is the point.
        name = image.split("/", 1)[1]
        tok = json.loads(_get(f"https://ghcr.io/token?scope=repository:{name}:pull",
                              accept="application/json"))["token"]
        body = _get(f"https://ghcr.io/v2/{name}/tags/list?n=1000", accept="application/json",
                    token=tok)
        return json.loads(body).get("tags") or []


# ---------------------------------------------------------------- pure parts

def highest_semver(names):
    """Highest plain vX.Y.Z (or X.Y.Z) name; pre-releases and other tags are ignored."""
    best = None
    for n in names:
        m = SEMVER.match(n)
        if m:
            key = tuple(int(x) for x in m.groups())
            if best is None or key > best[0]:
                best = (key, n)
    return best[1] if best else None


def feature_section(readme):
    """The text between the markers, or None when the README has no feature section."""
    if readme is None or MARK_START not in readme:
        return None
    body = readme.split(MARK_START, 1)[1]
    if MARK_END not in body:
        raise Refused("feature section has a start marker and no end marker")
    return body.split(MARK_END, 1)[0].strip()


def verified_bullets(repo, ref, section, exists):
    """Every top-level bullet with the paths it names; refuses a bullet with no existing path."""
    bullets, errors = [], []
    for line in section.splitlines():
        if not line.startswith("- "):
            continue
        paths = BACKTICK.findall(line)
        if not paths:
            errors.append(f"{repo}@{ref}: bullet names no path: {line[2:60]}")
        elif not any(exists(repo, ref, p) for p in paths):
            errors.append(f"{repo}@{ref}: no path in this bullet exists at the tag: {line[2:60]}")
        else:
            bullets.append(line)
    if errors:
        raise Refused("\n".join(errors))
    return bullets


def check_register(reg):
    ev = reg.get("evaluator") or {}
    if reg.get("tlp", "").upper() not in ("CLEAR", "TLP:CLEAR"):
        raise Refused(f"register export is not TLP:CLEAR (tlp={reg.get('tlp')!r})")
    if ev.get("register_sha") != reg.get("register_sha"):
        raise Refused("register export: evaluator ran on a different sha than the export")
    if ev.get("fail", 1) != 0 or ev.get("unknown", 1) != 0:
        raise Refused(f"register export: evaluator not green (fail={ev.get('fail')}, "
                      f"unknown={ev.get('unknown')})")


def refuse_denied(text, patterns):
    hits = sorted({p for p in patterns if re.search(p, text, re.IGNORECASE)})
    if hits:
        # Name the count, never the pattern: the list is secret.
        raise Refused(f"output matches {len(hits)} denylisted pattern(s); see the source rows")


def denylist_from_env():
    raw = os.environ.get("FEATURES_DENYLIST", "")
    pats = [p.strip() for p in raw.splitlines() if p.strip() and not p.startswith("#")]
    if not pats:
        raise Refused("FEATURES_DENYLIST is empty: the generator never runs unchecked")
    return pats


# ---------------------------------------------------------------- rendering

def render_components(rows):
    out = ["## Components", "",
           "Released versions only: the highest semver tag of each repository, or of its public "
           "image where the source is private.", "",
           "| Component | What it is | Released | Source |", "|---|---|---|---|"]
    for r in rows:
        src = f"[{r['repo']}](https://github.com/{r['repo']})" if r["public"] else "private"
        out.append(f"| {r['name']} | {r['role']} | {r['version'] or ('not released' if r['public'] else 'image not public')} | {src} |")
    return out


def render_capabilities(rows):
    out = ["## Capabilities", "",
           "Quoted from each repository's README at its released tag. Every line names a file "
           "that exists at that tag; the generator refuses a line that does not.", ""]
    missing = []
    for r in rows:
        if r.get("bullets"):
            out += [f"### {r['name']} {r['version']}", ""] + r["bullets"] + [""]
        elif r["public"] and r["version"]:
            missing.append(r["name"])
    if missing:
        out += ["Not yet described (no feature section in the README at the released tag): "
                + ", ".join(missing) + ".", ""]
    return out


def render_security(reg):
    ev = reg["evaluator"]
    out = ["## Security", "",
           f"From the security register's public edition, register `{reg['register_sha'][:12]}`, "
           f"as of {reg['as_of']}. The register's live evaluator checked it on {ev['run_at']}: "
           f"{ev['rows']} computed rows, {ev['fail']} failing, {ev['unknown']} unreadable. State and level "
           "are quoted as the register gives them. Rows marked *computed* are re-checked against "
           "released packages and the running fleet by that evaluator; the others are recorded by "
           "hand with the evidence shown.", ""]
    for sec in reg["sections"]:
        out += [f"### {sec.get('title') or sec.get('name')}", "",
                "| Feature | State | Level | What | Evidence |", "|---|---|---|---|---|"]
        for f in sec["features"]:
            state = f["state"] + (f" ({f['pct']}%)" if f.get("pct") is not None else "")
            if f.get("computed"):
                state += ", *computed*"
            ev_links = "; ".join(f"[{e['label']}]({e['url']})" for e in f.get("evidence", []))
            what = " ".join(str(f.get("what", "")).split()).replace("|", "\\|")
            out.append(f"| {f['name']} | {state} | {f['level']} | {what} | {ev_links} |")
        out.append("")
    return out


def render(components, register, stamp):
    out = ["# What Macula does today", "",
           "<!-- GENERATED by scripts/generate_features.py; do not edit. -->", "",
           "This document is generated from released code and from the security register's "
           "public edition. It states nothing that those sources do not.", "",
           f"Sources: {stamp}", ""]
    out += render_components(components) + [""]
    out += render_capabilities(components)
    out += render_security(register)
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------- assembly

def collect(gh, sources):
    rows = []
    for c in sources["components"]:
        row = {"name": c["name"], "role": c["role"], "repo": c["repo"],
               "public": c.get("source", "public") == "public", "version": None, "bullets": []}
        if row["public"]:
            tags = gh.tags(c["repo"])
            row["version"] = highest_semver([n for n, _ in tags])
            if row["version"]:
                section = feature_section(gh.readme(c["repo"], row["version"]))
                if section:
                    row["bullets"] = verified_bullets(
                        c["repo"], row["version"], section, gh.path_exists)
        elif c.get("image"):
            row["version"] = highest_semver(gh.image_tags(c["image"]))
        rows.append(row)
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "FEATURES.md"))
    ap.add_argument("--check", action="store_true", help="fail if --out differs from a fresh build")
    args = ap.parse_args(argv)
    try:
        patterns = denylist_from_env()
        with open(REGISTER, encoding="utf-8") as fh:
            register = json.load(fh)
        check_register(register)
        with open(SOURCES, encoding="utf-8") as fh:
            sources = json.load(fh)
        rows = collect(GitHub(os.environ.get("GH_TOKEN")), sources)
        stamp = "; ".join([f"{r['repo']} {r['version']}" for r in rows if r["version"]]
                          + [f"security register {register['register_sha'][:12]}"])
        text = render(rows, register, stamp)
        refuse_denied(text, patterns)
    except Refused as e:
        print(f"refused: {e}", file=sys.stderr)
        return 2
    if args.check:
        current = open(args.out, encoding="utf-8").read() if os.path.exists(args.out) else ""
        if current != text:
            print(f"{args.out} is stale: regenerate it", file=sys.stderr)
            return 1
        return 0
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
