# User output in Simplified Technical English

Use ASD-STE100 Simplified Technical English, Issue 9, for all prose that this
loop sends to the user. This includes progress messages, questions, PR text,
and the final reply. Keep code, commands, paths, identifiers, URLs, and quoted
source text exact. Do not change their meaning to satisfy a writing rule.

Use the [official Issue 9 standard](https://www.asd-ste100.org/STE_downloads.html)
for its writing rules and dictionary. Use approved words with their approved
meanings and parts of speech. Use consistent technical nouns and verbs for
software terms. Write short, direct sentences in the active voice. Put one
instruction in each procedural sentence. Use American English spelling.

Before each user-facing message, review the draft against Issue 9. When local
tools are available, save the draft in a temporary file and run:

```bash
python3 <skill-dir>/scripts/ste_sentence_gate.py <draft-file>
```

The script checks sentence length and does not send text to a service. It is a
first check only: a pass does not prove compliance with the dictionary or all
writing rules. Revise failures, then review the words, grammar, and meaning.
If local tools are unavailable, do the same review before sending.
Do not claim that the script certifies ASD-STE100 compliance.

Example:

- Avoid: "The implementation has been successfully validated, and the results
  have been made available for your consideration."
- Use: "The check passed. Read the result in the report."
