#!/usr/bin/env python3
"""Tests for generate_features.py: each refusal is what keeps the document from claiming more than is built."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_features as g  # noqa: E402


class FakeGitHub:
    def __init__(self, tags=None, readmes=None, files=None, images=None):
        self._tags = tags or {}
        self._readmes = readmes or {}
        self._files = files or set()
        self._images = images or {}

    def tags(self, repo):
        return [(n, "0" * 40) for n in self._tags.get(repo, [])]

    def readme(self, repo, ref):
        return self._readmes.get((repo, ref))

    def path_exists(self, repo, ref, path):
        return (repo, ref, path) in self._files

    def image_tags(self, image):
        return self._images.get(image, [])


def register(**over):
    reg = {"tlp": "TLP:CLEAR", "register_sha": "a" * 40, "as_of": "2026-10-07",
           "evaluator": {"register_sha": "a" * 40, "run_at": "2026-10-07T03:00:00Z",
                         "rows": 68, "fail": 0, "unknown": 0},
           "sections": [{"title": "Transport", "features": [
               {"name": "Hybrid PQ handshake", "state": "done", "level": "High",
                "what": "ML-KEM-1024 with X25519", "computed": 1,
                "evidence": [{"label": "macula 14.2.1", "url": "https://hex.pm/packages/macula"}]},
               {"name": "Sealing", "state": "progress", "pct": 60, "level": "Strong",
                "what": "payload sealing", "computed": 0, "evidence": []}]}]}
    reg.update(over)
    return reg


README = "intro\n<!-- features:start -->\n- Calls a procedure (`src/macula.erl`)\n<!-- features:end -->\n"


class SemverTest(unittest.TestCase):
    def test_highest_is_numeric_not_lexical_and_ignores_prereleases(self):
        self.assertEqual(g.highest_semver(["v1.9.0", "v1.10.0", "v2.0.0-rc1", "latest"]), "v1.10.0")

    def test_none_when_nothing_released(self):
        self.assertIsNone(g.highest_semver(["main", "latest"]))


class CapabilityTest(unittest.TestCase):
    def test_bullet_with_existing_path_is_kept(self):
        gh = FakeGitHub(files={("o/r", "v1.0.0", "src/macula.erl")})
        sec = g.feature_section(README)
        self.assertEqual(g.verified_bullets("o/r", "v1.0.0", sec, gh.path_exists),
                         ["- Calls a procedure (`src/macula.erl`)"])

    def test_bullet_whose_path_is_gone_is_refused(self):
        gh = FakeGitHub()
        with self.assertRaises(g.Refused):
            g.verified_bullets("o/r", "v1.0.0", g.feature_section(README), gh.path_exists)

    def test_bullet_without_any_path_is_refused(self):
        sec = "- Does everything, everywhere"
        with self.assertRaises(g.Refused):
            g.verified_bullets("o/r", "v1.0.0", sec, lambda *a: True)

    def test_readme_without_markers_has_no_section(self):
        self.assertIsNone(g.feature_section("just a readme"))
        self.assertIsNone(g.feature_section(None))

    def test_unterminated_section_is_refused(self):
        with self.assertRaises(g.Refused):
            g.feature_section("<!-- features:start -->\n- x (`a`)")

    def test_capabilities_read_at_the_released_tag_only(self):
        gh = FakeGitHub(tags={"o/r": ["v1.0.0", "v0.9.0"]},
                        readmes={("o/r", "v1.0.0"): README, ("o/r", "main"): "- unreleased (`x`)"},
                        files={("o/r", "v1.0.0", "src/macula.erl")})
        rows = g.collect(gh, {"components": [{"name": "macula", "role": "SDK", "repo": "o/r"}]})
        self.assertEqual(rows[0]["version"], "v1.0.0")
        self.assertEqual(len(rows[0]["bullets"]), 1)

    def test_private_component_takes_its_public_image_version_and_no_capabilities(self):
        gh = FakeGitHub(images={"ghcr.io/o/station": ["0.8.0", "0.7.9", "latest"]})
        rows = g.collect(gh, {"components": [{"name": "station", "role": "node", "repo": "o/station",
                                              "source": "private", "image": "ghcr.io/o/station"}]})
        self.assertEqual(rows[0]["version"], "0.8.0")
        self.assertEqual(rows[0]["bullets"], [])


class RegisterTest(unittest.TestCase):
    def test_green_clear_export_passes(self):
        g.check_register(register())

    def test_failing_evaluator_is_refused(self):
        reg = register()
        reg["evaluator"]["fail"] = 1
        with self.assertRaises(g.Refused):
            g.check_register(reg)

    def test_unknown_facts_are_refused(self):
        reg = register()
        reg["evaluator"]["unknown"] = 2
        with self.assertRaises(g.Refused):
            g.check_register(reg)

    def test_evaluator_on_another_sha_is_refused(self):
        reg = register()
        reg["evaluator"]["register_sha"] = "b" * 40
        with self.assertRaises(g.Refused):
            g.check_register(reg)

    def test_non_clear_export_is_refused(self):
        with self.assertRaises(g.Refused):
            g.check_register(register(tlp="TLP:AMBER"))

    def test_state_and_level_are_quoted_exactly_and_computed_is_marked(self):
        text = "\n".join(g.render_security(register()))
        self.assertIn("| Hybrid PQ handshake | done, *computed* | High |", text)
        self.assertIn("| Sealing | progress (60%) | Strong |", text)
        self.assertIn("register `aaaaaaaaaaaa`, as of 2026-10-07", text)


class DenylistTest(unittest.TestCase):
    def test_match_is_refused_without_naming_the_pattern(self):
        with self.assertRaises(g.Refused) as ctx:
            g.refuse_denied("runs on SecretHost today", [r"secrethost"])
        self.assertNotIn("secrethost", str(ctx.exception).lower())

    def test_empty_denylist_never_runs_unchecked(self):
        os.environ.pop("FEATURES_DENYLIST", None)
        with self.assertRaises(g.Refused):
            g.denylist_from_env()


if __name__ == "__main__":
    unittest.main()
