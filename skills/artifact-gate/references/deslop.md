# Deslop: design that reads as machine-generated

A generated page reaches for the same defaults every time, and a reader has
learned to recognise them. Each one below is a choice nobody made. The fix is
to make the choice, not to soften the default: a gradient made subtler is
still a gradient nobody decided on.

The catalogue follows impeccable's own craft floor (its "Refuse" list,
Apache-2.0) and its detector. Any of these can be right when the brief asks
for it. Reaching for one when nothing asked is the tell.

## What `impeccable detect` catches

Measured 2026-10-21 against a page built to contain every pattern here. These
rule ids fired; a finding names the id.

| rule id | the tell | instead |
|---|---|---|
| `gradient-text` | gradient fill on headings | emphasis from weight and size |
| `dark-glow` | zero-offset coloured halo (box- or text-shadow) | a shadow with offset and soft blur, or none |
| `side-tab` | thick coloured border on one side of a card or callout | a full border, a background step, or nothing |
| `hero-eyebrow-chip` | tiny tracked-caps label above the hero heading | delete it; the heading carries itself |
| `ai-color-palette` | purple-violet gradients, cyan on dark | a palette taken from the subject |
| `overused-font` | Inter, Roboto, Geist, Space Grotesk and similar | a face whose character fits the content |
| `marketing-buzzword` | supercharge, seamless, empower, enterprise-grade | say what the thing does |

Its `--help` also lists em-dash overuse as an advisory rule. It did not fire on
a short page dense with em dashes, so read the copy for it yourself.

## What only a reader catches

The same test page carried all of these, and the scan reported none of them.

**Page scaffolds**

- Same-size cards of icon, heading and sentence as the whole page structure.
  Cards nested inside cards are always wrong.
- The hero-metric row: big number, small label, three supporting stats.
- Section numbers (01 / 02 / 03) where the order carries nothing.
- A modal for a task that needs neither interruption nor protected focus.

**Surfaces**

- Glass and backdrop blur as decoration.
- Emoji or Unicode glyphs standing in for icons. Use one drawn set with one
  stroke and weight.
- Monospace as a costume for "technical" rather than for code, data or
  measurement.
- Hard offset shadows (`4px 4px 0`) on a page that did not choose a
  neobrutalist style.
- Sparklines, progress rings and soft rounded rectangles standing in for
  content.
- Light or dark chosen by category ("it's a dev tool, so dark") rather than by
  where and how the page is read.

**What a generated page forgets.** Text selection colour, scrollbars, focus
rings, underline offset and tabular numerals ship with browser defaults.
Theming them from the palette is the cheapest sign a page was built, not
assembled.

**Copy.** Generic calls to action ("Get started →"), the em-dash cadence, and
three-adjective feature blurbs. Controls name their action; errors name the
problem and the recovery.

## Using the scan

1. Run `detect` and read every finding against the rendered page.
2. Fix a real finding by deciding what the element should be.
3. Silence a finding only for a reason you can name, with the narrowest scope
   (`impeccable ignores add-value <rule> <value> --reason "..."`). Never with
   `add-rule` to make a page pass.
4. Then walk the reader-only list by eye. A clean scan covers the first table
   only.
