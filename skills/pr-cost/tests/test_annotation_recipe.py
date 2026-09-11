"""The manual annotation preserves the reader's reported estimate basis."""
from pathlib import Path
import json
import os
import re
import subprocess
import unittest

SKILL = Path(__file__).resolve().parents[1]


def render_flag(document, flag, usage):
    """Render one flag value from the documented recipe through its own key()."""
    helper = re.search(r'key\(\) \{.*?\n\}', document, re.S).group(0)
    value = re.search(r'^  --' + re.escape(flag) + r' (.*?) *\\?$', document, re.M).group(1)
    env = dict(os.environ, USAGE=json.dumps(usage), READER='synthetic-reader')
    return subprocess.check_output(
        ['bash', '-c', helper + '\nprintf "%s" ' + value], env=env, text=True
    )


class AnnotationRecipeTest(unittest.TestCase):
    def test_recipe_passes_the_reader_basis_as_a_typed_field(self):
        # The basis used to ride along inside --notes, which is free text a
        # comment cannot label. It now has its own field, so the property this
        # file guards -- the reader's basis survives into the annotation --
        # is checked on that field instead.
        document = (SKILL / 'references/annotate.md').read_text()
        for basis in ('model-rates', 'default-rates', 'provider-reported'):
            with self.subTest(basis=basis):
                rendered = render_flag(document, 'usd-basis', {'usd_basis': basis})
                self.assertEqual(rendered, basis)

    def test_recipe_passes_the_token_split_from_the_reader(self):
        # Without these three the comment shows only the merged tokens_in,
        # which is what was misread as uncached input.
        document = (SKILL / 'references/annotate.md').read_text()
        usage = {
            'uncached_input_tokens': 2956,
            'cache_read_input_tokens': 697885763,
            'cache_creation_input_tokens': 22807403,
        }
        for flag, key in (
            ('tokens-in-uncached', 'uncached_input_tokens'),
            ('tokens-in-cache-read', 'cache_read_input_tokens'),
            ('tokens-in-cache-write', 'cache_creation_input_tokens'),
        ):
            with self.subTest(flag=flag):
                self.assertEqual(render_flag(document, flag, usage), str(usage[key]))

    def test_notes_keep_the_token_contract_caveat(self):
        document = (SKILL / 'references/annotate.md').read_text()
        notes = render_flag(document, 'notes', {'usd_basis': 'model-rates'})
        self.assertIn('cached tokens are not added again', notes)


if __name__ == '__main__':
    unittest.main()
