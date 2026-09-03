#!/usr/bin/env python3
"""Fixtures for model-catalog's arithmetic and freshness rules.

1516 lines shipped with no tests. These cover the two things the catalog is
trusted for and cannot be eyeballed: the price scaling, and the rule that
decides whether a cached catalog may be presented as current.

That freshness rule is stated three times in the source -- "Unknown age is
treated as stale, never as fresh", "a null stale_after reads as stale", "Data
of unknown age can never be shown as recent" -- and was implemented for three
of the four ways age can be unusable. Absent, null, and the UNKNOWN_DATA_AGE
sentinel all read as stale. A stamp that could not be parsed raised ValueError
out of is_stale() instead, so a damaged cache crashed the tool rather than
being treated as stale and rebuilt, and --refresh-if-stale could not recover
from it without deleting the file by hand.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import time
import unittest
from datetime import datetime, timezone

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "bin" / "model-catalog"


def load():
    loader = importlib.machinery.SourceFileLoader("model_catalog", str(SCRIPT))
    spec = importlib.util.spec_from_loader("model_catalog", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


mc = load()

PAST = "2020-01-01T00:00:00Z"
FUTURE = "2099-01-01T00:00:00Z"


class PriceTest(unittest.TestCase):
    def test_per_token_string_scales_to_per_million(self) -> None:
        # OpenRouter sends per-token USD as a string; a factor-of-1e6 slip here
        # is invisible in the output and wrong by six orders of magnitude.
        self.assertEqual(mc.price_per_mtok("0.000003"), 3.0)
        self.assertEqual(mc.price_per_mtok(3e-6), 3.0)
        self.assertEqual(mc.price_per_mtok("1e-6"), 1.0)

    def test_free_is_zero_not_missing(self) -> None:
        # 0.0 and None mean different things downstream; `if not price` would
        # collapse them.
        self.assertEqual(mc.price_per_mtok("0"), 0.0)
        self.assertIsNotNone(mc.price_per_mtok("0"))

    def test_negative_sentinel_is_unknown_not_a_negative_price(self) -> None:
        self.assertIsNone(mc.price_per_mtok("-1"))

    def test_unusable_input_is_none_never_a_number(self) -> None:
        for value in (None, "", "abc", [1], {}):
            with self.subTest(value):
                self.assertIsNone(mc.price_per_mtok(value))


class StalenessTest(unittest.TestCase):
    """Each case is one way age can be unusable. All must read as stale."""

    def test_expired_stamp_is_stale(self) -> None:
        self.assertTrue(mc.is_stale({"stale_after": PAST}))

    def test_future_stamp_is_fresh(self) -> None:
        # The control. Without it every assertion here is satisfied by an
        # is_stale() hard-wired to True, which would be the easiest possible
        # way to pass a fail-closed test suite.
        self.assertFalse(mc.is_stale({"stale_after": FUTURE}))
        self.assertFalse(mc.is_very_stale({"data_as_of": mc.now_iso()}))

    def test_absent_stamp_is_stale(self) -> None:
        self.assertTrue(mc.is_stale({}))
        self.assertTrue(mc.is_very_stale({}))

    def test_null_stamp_is_stale(self) -> None:
        self.assertTrue(mc.is_stale({"stale_after": None}))

    def test_unknown_sentinel_is_stale(self) -> None:
        self.assertTrue(mc.is_very_stale({"data_as_of": mc.UNKNOWN_DATA_AGE}))

    def test_corrupt_stamp_is_stale_and_does_not_raise(self) -> None:
        # Red against the pre-fix script: both of these raised ValueError.
        for junk in ("garbage", "2020-13-45", "not-a-date", "  "):
            with self.subTest(junk):
                self.assertTrue(mc.is_stale({"stale_after": junk}))
                self.assertTrue(mc.is_very_stale({"data_as_of": junk}))

    def test_non_string_stamp_is_stale_and_does_not_raise(self) -> None:
        for junk in (12345, [], {}, True):
            with self.subTest(junk):
                self.assertTrue(mc.is_stale({"stale_after": junk}))

    def test_date_only_stamp_is_accepted(self) -> None:
        # Docs snapshots carry a bare date; treating those as corrupt would
        # make every seeded catalog permanently stale.
        self.assertFalse(mc.is_stale({"stale_after": "2099-01-01"}))
        self.assertTrue(mc.is_stale({"stale_after": "2020-01-01"}))

    def test_very_stale_uses_data_age_not_file_age(self) -> None:
        # Rebuilding a static snapshot must not make the snapshot newer.
        old = {"data_as_of": PAST, "generated_at": mc.now_iso()}
        self.assertTrue(mc.is_very_stale(old))

    def test_very_stale_threshold_is_the_documented_one(self) -> None:
        # Straddle VERY_STALE_AFTER_SECONDS from both sides. A one-sided
        # assertion passes on a predicate stuck at either constant.
        def stamp(offset_seconds: float) -> str:
            moment = datetime.fromtimestamp(time.time() - offset_seconds, timezone.utc)
            return moment.replace(microsecond=0).isoformat().replace("+00:00", "Z")

        inside = stamp(mc.VERY_STALE_AFTER_SECONDS - 3600)
        outside = stamp(mc.VERY_STALE_AFTER_SECONDS + 3600)
        self.assertFalse(mc.is_very_stale({"data_as_of": inside}), inside)
        self.assertTrue(mc.is_very_stale({"data_as_of": outside}), outside)


class ParseIsoOrNoneTest(unittest.TestCase):
    def test_valid_stamps_parse(self) -> None:
        self.assertIsNotNone(mc.parse_iso_or_none(PAST))
        self.assertIsNotNone(mc.parse_iso_or_none("2020-01-01"))

    def test_unusable_stamps_are_none(self) -> None:
        for junk in ("garbage", "", "   ", None, 5, [], "2020-13-45"):
            with self.subTest(junk):
                self.assertIsNone(mc.parse_iso_or_none(junk))


class ContextWindowTest(unittest.TestCase):
    def test_k_context_tooltip_scales(self) -> None:
        self.assertEqual(mc.parse_cursor_context_window("200k context"), 200000)

    def test_explicit_context_window_is_read(self) -> None:
        self.assertEqual(
            mc.parse_cursor_context_window("128,000 context window"), 128000
        )

    def test_unrecognized_tooltip_is_none_not_a_guess(self) -> None:
        # A wrong context window silently misroutes a model choice; None
        # merely reports it as unknown.
        for value in (None, "", "no numbers here", "1M ctx"):
            with self.subTest(value):
                self.assertIsNone(mc.parse_cursor_context_window(value))


if __name__ == "__main__":
    unittest.main()
