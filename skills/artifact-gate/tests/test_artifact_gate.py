"""Every gate forced red, and proven not to fire on good input.

A gate with only a clean case certifies nothing: it passes identically when it
has stopped measuring anything. Each test below constructs input that MUST trip
one gate, and the clean cases prove the same gate stays quiet on valid input.
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import check_html  # noqa: E402
import verify_links  # noqa: E402


def problems(html, **kw):
    return check_html.check(html, **kw)


def only(found, needle):
    return [p for p in found if needle in p]


class CheckHtmlTest(unittest.TestCase):
    CLEAN = '<section id="a"><p>hi</p><a href="#a">jump</a></section>'

    def test_clean_page_has_no_findings(self):
        self.assertEqual(problems(self.CLEAN), [])

    def test_unbalanced_tag_is_caught(self):
        self.assertTrue(only(problems('<div><p>x</div>'), "unbalanced <p>"))

    def test_tag_names_match_not_prefixes(self):
        # <pre> must not count as <p>, and <link> must not count as <li>.
        # A probe wrong in this way looks exactly like a broken page.
        html = '<pre>code</pre><link href="https://e.example/x">'
        self.assertEqual(only(problems(html), "unbalanced <p>"), [])
        self.assertEqual(only(problems(html), "unbalanced <li>"), [])

    def test_self_closing_tag_does_not_unbalance(self):
        self.assertEqual(only(problems('<p>x</p><br/>'), "unbalanced"), [])

    def test_wrapper_tags_are_refused(self):
        self.assertTrue(only(problems('<html><p>x</p></html>'), "publish step adds the wrapper"))

    def test_wrapper_allowed_when_standalone(self):
        found = problems('<html><p>x</p></html>', allow_wrapper=True)
        self.assertEqual(only(found, "wrapper"), [])

    def test_relative_href_is_refused(self):
        self.assertTrue(only(problems('<a href="page.html">x</a>'), "non-absolute href"))

    def test_same_page_fragment_is_allowed(self):
        html = '<section id="s"></section><a href="#s">x</a>'
        self.assertEqual(only(problems(html), "non-absolute href"), [])

    def test_duplicate_id_is_caught(self):
        self.assertTrue(only(problems('<p id="x"></p><p id="x"></p>'), "duplicate id"))

    def test_dead_anchor_is_caught(self):
        self.assertTrue(only(problems('<a href="#nowhere">x</a>'), "dead anchor"))

    def test_count_claim_mismatch_is_caught(self):
        html = '<p>three questions</p><span class="qnum"></span><span class="qnum"></span>'
        self.assertTrue(only(problems(html, count_claims=[("qnum", "questions")]),
                             "self-claim mismatch"))

    def test_absent_count_claim_is_a_failure(self):
        # Deleting the sentence must not retire the gate: that is how it goes
        # quiet exactly when the document is largest.
        html = '<span class="qnum"></span>'
        self.assertTrue(only(problems(html, count_claims=[("qnum", "questions")]),
                             "never states the count"))

    def test_count_claim_agrees_in_words_and_digits(self):
        two = '<span class="qnum"></span><span class="qnum"></span>'
        for claim in ("two questions", "2 questions"):
            found = problems(f"<p>{claim}</p>{two}", count_claims=[("qnum", "questions")])
            self.assertEqual(only(found, "self-claim"), [], claim)
            self.assertEqual(only(found, "never states"), [], claim)

    def test_count_claim_survives_past_the_word_list(self):
        many = '<span class="qnum"></span>' * 40
        found = problems(f"<p>40 questions</p>{many}", count_claims=[("qnum", "questions")])
        self.assertEqual(only(found, "self-claim"), [])


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args],
                          capture_output=True, text=True, check=False)


class VerifyLinksTest(unittest.TestCase):
    HOST = "git.example.com"
    NS = "example-org"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self.tmp.name) / "widget"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "t@t.invalid")
        git(self.repo, "config", "user.name", "t")
        git(self.repo, "config", "commit.gpgsign", "false")
        (self.repo / "app.py").write_text("one\ntwo\ndef widget():\n")
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "seed")
        self.sha = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        git(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        self.repos = {"widget": str(self.repo)}

    def tearDown(self):
        self.tmp.cleanup()

    def run_verify(self, html):
        return verify_links.verify(html, self.repos, self.HOST, self.NS, "main")[0]

    def run_notes(self, html):
        return verify_links.verify(html, self.repos, self.HOST, self.NS, "main")[1]

    def url(self, ref, path="app.py", frag=""):
        return f"https://{self.HOST}/{self.NS}/widget/-/blob/{ref}/{path}{frag}"

    def test_pinned_link_with_live_anchor_passes(self):
        html = (f'<a href="{self.url(self.sha, frag="#L3")}" '
                f'data-expect="def widget">widget()</a>')
        self.assertEqual(self.run_verify(html), [])

    def test_missing_clone_fails_closed(self):
        found = verify_links.verify("", {"widget": "/nonexistent/clone"},
                                    self.HOST, self.NS, "main")[0]
        self.assertTrue(only(found, "CANNOT be verified"))

    def test_line_anchor_on_a_moving_ref_is_refused(self):
        html = f'<a href="{self.url("main", frag="#L3")}">x</a>'
        self.assertTrue(only(self.run_verify(html), "line anchor on a moving ref"))

    def test_link_without_anchor_may_use_a_branch(self):
        html = f'<a href="{self.url("main")}">x</a>'
        self.assertEqual(self.run_verify(html), [])

    def test_unreachable_sha_is_a_dead_citation(self):
        # Exists in the object database, reachable from no branch. cat-file
        # answers `commit` for it, which is why existence is not the check.
        (self.repo / "app.py").write_text("one\ntwo\ndef widget():\nextra\n")
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "orphan")
        orphan = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        git(self.repo, "reset", "-q", "--hard", self.sha)
        self.assertEqual(git(self.repo, "cat-file", "-t", orphan).stdout.strip(), "commit")
        html = f'<a href="{self.url(orphan, frag="#L3")}">x</a>'
        self.assertTrue(only(self.run_verify(html), "not an ancestor"))

    def test_nonexistent_ref_is_caught(self):
        html = f'<a href="{self.url("0" * 40, frag="#L3")}">x</a>'
        found = self.run_verify(html)
        self.assertTrue(only(found, "does not exist") or only(found, "not an ancestor"))

    def test_missing_file_at_that_ref_is_caught(self):
        html = f'<a href="{self.url(self.sha, path="gone.py", frag="#L1")}">x</a>'
        self.assertTrue(only(self.run_verify(html), "absent at"))

    def test_line_past_end_of_file_is_caught(self):
        html = f'<a href="{self.url(self.sha, frag="#L99")}">x</a>'
        self.assertTrue(only(self.run_verify(html), "link cites L99"))

    def test_line_exists_but_no_longer_says_it(self):
        # The failure this whole script exists for: the link resolves, the line
        # is in range, and the claim about it is false.
        html = (f'<a href="{self.url(self.sha, frag="#L1")}" '
                f'data-expect="def widget">widget()</a>')
        self.assertTrue(only(self.run_verify(html), "no longer contains"))

    def test_unrecognised_form_is_reported_not_skipped(self):
        html = f'<a href="https://{self.HOST}/{self.NS}/widget/-/wat/7">x</a>'
        self.assertTrue(only(self.run_verify(html), "unrecognised link form"))

    def test_api_only_form_is_counted_not_refused(self):
        # A merge-request citation is legitimate and common. Refusing it would
        # mean the only way to publish such a page is to bypass the gate, which
        # is how a gate stops being run. It must pass AND stay visible.
        html = f'<a href="https://{self.HOST}/{self.NS}/widget/-/merge_requests/1776">x</a>'
        self.assertEqual(self.run_verify(html), [])
        self.assertTrue(only(self.run_notes(html), "needs API access"))

    def test_api_only_form_is_not_silently_counted_as_verified(self):
        # The third state must not collapse into "verified" either: a page of
        # nothing but MR links has verified zero code links.
        html = f'<a href="https://{self.HOST}/{self.NS}/widget/-/issues/7">x</a>'
        self.assertTrue(only(self.run_notes(html), "verified 0 link(s)"))

    def test_unknown_repo_is_reported(self):
        html = (f'<a href="https://{self.HOST}/{self.NS}/other/-/blob/'
                f'{self.sha}/app.py">x</a>')
        self.assertTrue(only(self.run_verify(html), "unknown repo"))


if __name__ == "__main__":
    unittest.main()
