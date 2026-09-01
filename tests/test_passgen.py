#!/usr/bin/env python3
"""Tests for the passgen engine, ported from the macOS app's XCTest suite.

Generation is random, so every property is asserted over many trials
rather than a single sample.

    python3 tests/test_passgen.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import importlib.util

_spec = importlib.util.spec_from_loader(
    "passgen",
    importlib.machinery.SourceFileLoader(
        "passgen",
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "passgen"),
    ),
)
passgen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(passgen)

TRIALS = 200


class RandomPasswordTests(unittest.TestCase):
    def generate(self, **kwargs):
        opts = dict(length=12, upper=True, numbers=True, symbols=True,
                    exclude_ambiguous=False)
        opts.update(kwargs)
        return passgen.generate_random(**opts)

    def test_length_is_exact(self):
        for length in range(8, 33):
            self.assertEqual(len(self.generate(length=length)), length)

    def test_always_contains_lowercase(self):
        for _ in range(TRIALS):
            self.assertTrue(any(c in passgen.LOWERCASE for c in self.generate()))

    def test_contains_uppercase_when_enabled(self):
        for _ in range(TRIALS):
            self.assertTrue(any(c in passgen.UPPERCASE for c in self.generate(upper=True)))

    def test_no_uppercase_when_disabled(self):
        for _ in range(TRIALS):
            pw = self.generate(upper=False)
            self.assertFalse(any(c in passgen.UPPERCASE for c in pw))

    def test_contains_numbers_when_enabled(self):
        for _ in range(TRIALS):
            self.assertTrue(any(c in passgen.NUMBERS for c in self.generate(numbers=True)))

    def test_no_numbers_when_disabled(self):
        for _ in range(TRIALS):
            self.assertFalse(any(c in passgen.NUMBERS for c in self.generate(numbers=False)))

    def test_contains_symbols_when_enabled(self):
        for _ in range(TRIALS):
            self.assertTrue(any(c in passgen.SYMBOLS for c in self.generate(symbols=True)))

    def test_no_symbols_when_disabled(self):
        for _ in range(TRIALS):
            self.assertFalse(any(c in passgen.SYMBOLS for c in self.generate(symbols=False)))

    def test_excludes_ambiguous_characters(self):
        for _ in range(TRIALS):
            pw = self.generate(length=32, exclude_ambiguous=True)
            self.assertFalse(any(c in passgen.AMBIGUOUS for c in pw))

    def test_ambiguous_exclusion_keeps_length(self):
        for length in (8, 16, 32):
            self.assertEqual(len(self.generate(length=length, exclude_ambiguous=True)), length)

    def test_includes_at_least_one_of_each_enabled_type(self):
        for _ in range(TRIALS):
            pw = self.generate(length=8)
            self.assertTrue(any(c in passgen.LOWERCASE for c in pw))
            self.assertTrue(any(c in passgen.UPPERCASE for c in pw))
            self.assertTrue(any(c in passgen.NUMBERS for c in pw))
            self.assertTrue(any(c in passgen.SYMBOLS for c in pw))

    def test_type_guarantee_keeps_exact_length_at_minimum(self):
        # Four seeded characters against the 8-character floor.
        for _ in range(TRIALS):
            self.assertEqual(len(self.generate(length=8)), 8)

    def test_only_lowercase_when_everything_else_off(self):
        for _ in range(TRIALS):
            pw = self.generate(upper=False, numbers=False, symbols=False)
            self.assertTrue(all(c in passgen.LOWERCASE for c in pw))

    def test_passwords_are_not_repeated(self):
        seen = {self.generate(length=20) for _ in range(TRIALS)}
        self.assertEqual(len(seen), TRIALS)


class PinTests(unittest.TestCase):
    def test_length(self):
        for length in range(4, 13):
            self.assertEqual(len(passgen.generate_pin(length, True)), length)

    def test_only_digits(self):
        for _ in range(TRIALS):
            self.assertTrue(passgen.generate_pin(12, False).isdigit())

    def test_no_consecutive_repeats_when_enabled(self):
        for _ in range(TRIALS):
            pin = passgen.generate_pin(12, True)
            self.assertFalse(any(a == b for a, b in zip(pin, pin[1:])),
                             f"consecutive repeat in {pin}")

    def test_repeats_are_possible_when_disabled(self):
        found = any(
            any(a == b for a, b in zip(pin, pin[1:]))
            for pin in (passgen.generate_pin(12, False) for _ in range(TRIALS))
        )
        self.assertTrue(found, "expected at least one consecutive repeat across trials")


class HexTests(unittest.TestCase):
    def test_length(self):
        for length in range(8, 65, 2):
            self.assertEqual(len(passgen.generate_hex(length, True)), length)

    def test_uppercase_alphabet(self):
        for _ in range(TRIALS):
            self.assertTrue(all(c in "0123456789ABCDEF" for c in passgen.generate_hex(32, True)))

    def test_lowercase_alphabet(self):
        for _ in range(TRIALS):
            self.assertTrue(all(c in "0123456789abcdef" for c in passgen.generate_hex(32, False)))


class PassphraseTests(unittest.TestCase):
    def setUp(self):
        self.words = passgen.load_wordlist()

    def test_wordlist_is_unique_and_expected_size(self):
        self.assertEqual(len(self.words), 521)
        self.assertEqual(len(set(self.words)), len(self.words))

    def test_word_count(self):
        for count in range(3, 9):
            phrase = passgen.generate_passphrase(count, "-", False, False, self.words)
            self.assertEqual(len(phrase.split("-")), count)

    def test_separators(self):
        for sep in ("-", "_", ".", " "):
            phrase = passgen.generate_passphrase(4, sep, False, False, self.words)
            self.assertEqual(len(phrase.split(sep)), 4)

    def test_capitalize_enabled(self):
        phrase = passgen.generate_passphrase(4, "-", True, False, self.words)
        for word in phrase.split("-"):
            self.assertTrue(word[0].isupper(), f"{word} is not capitalized")

    def test_capitalize_disabled(self):
        phrase = passgen.generate_passphrase(4, "-", False, False, self.words)
        self.assertEqual(phrase, phrase.lower())

    def test_number_appended(self):
        for _ in range(TRIALS):
            phrase = passgen.generate_passphrase(4, "-", False, True, self.words)
            parts = phrase.split("-")
            self.assertEqual(len(parts), 5)
            self.assertTrue(parts[-1].isdigit())
            self.assertTrue(10 <= int(parts[-1]) <= 999)

    def test_words_come_from_the_list(self):
        phrase = passgen.generate_passphrase(8, "-", False, False, self.words)
        for word in phrase.split("-"):
            self.assertIn(word, self.words)


class PronounceableTests(unittest.TestCase):
    def test_length_without_numbers(self):
        for length in range(6, 33):
            pw = passgen.generate_pronounceable(length, False, False)
            self.assertEqual(len(pw), length)

    def test_numbers_add_two_digits(self):
        for _ in range(TRIALS):
            pw = passgen.generate_pronounceable(12, False, True)
            self.assertEqual(len(pw), 14)
            self.assertTrue(pw[-2:].isdigit())

    def test_capitalize_first_letter(self):
        for _ in range(TRIALS):
            self.assertTrue(passgen.generate_pronounceable(12, True, False)[0].isupper())

    def test_lowercase_when_not_capitalized(self):
        for _ in range(TRIALS):
            self.assertTrue(passgen.generate_pronounceable(12, False, False).islower())


class CliTests(unittest.TestCase):
    def test_each_type_runs(self):
        for argv in (["random"], ["pronounceable"], ["passphrase"], ["pin"], ["hex"]):
            self.assertEqual(passgen.main(argv), 0)

    def test_length_is_clamped_to_bounds(self):
        parser = passgen.build_parser()
        self.assertEqual(len(passgen.generate(parser.parse_args(["random", "--length", "999"]))), 32)
        self.assertEqual(len(passgen.generate(parser.parse_args(["random", "--length", "1"]))), 8)
        self.assertEqual(len(passgen.generate(parser.parse_args(["pin", "--length", "0"]))), 4)


if __name__ == "__main__":
    unittest.main(verbosity=2, buffer=True)
