# exubercrit

The shared critical-value store for the recursive right-tailed unit root tests. It holds the simulated tables (`data/lag<L>/n<N>.bin.xz`), the R script that simulates them (`scripts/simulate-crit.R`, using `radf_nested()` from exubercore) and the source of the Railway proxy that serves them (`scripts/exuber-fn.ts`). `README.md` explains the method, the file format and how the tables are served. Read it before you state what has been simulated or how.

The clients are `exuber/R/crit-bucket.R` and `pyexuber/src/exuber/crit.py`. A change to the binary layout needs a matching change in both parsers. The tables are simulated data, so do not edit them by hand; run `scripts/simulate-crit.R` instead.

## Writing style (all user-facing text)

Applies to READMEs, vignettes, the website, `docs/`, NEWS/CHANGELOG,
roxygen and docstrings, and any prose a reader sees. Code comments and
CLAUDE.md files follow it too.

**Voice.** An applied economist writing for colleagues who also want
ordinary readers to be able to run the test. Precise, sober, a little
plain-spoken. Define a term at first use (what "explosive" means, what a
critical value is for) and give the idea in words before the formula.

**Rewrite, do not substitute.** Swapping an em dash for a comma, colon or
hyphen keeps the machine-written rhythm and is not acceptable. If a
sentence needed a dash, it was carrying two thoughts: split it into two
sentences, or fold the aside into the grammar (a relative clause, a
parenthesis only for a true aside, or a separate sentence). No U+2014 and
no spaced hyphen standing in for one. En dashes stay for numeric ranges
and joint names (Phillips–Shi–Yu).

**Patterns to remove at the sentence level.**
- Fragments stacked for effect, and "X, not Y" or "not just X, but Y"
  framings. State the claim directly.
- Triplets used for rhythm, and sentences that announce what they are about
  to say ("Importantly,", "It is worth noting that", "In essence").
- Telegraphic notes (dropped articles, arrows, semicolon chains, "confirmed,
  zero new code"). Write full sentences with a subject and a verb.
- Status-report voice: "genuinely", "confirmed", "now done", "picked
  clean", "the most topical candidate". Say what is true and give the date
  if it matters.
- Marketing and filler words: seamlessly, robust (unless a statistical
  sense is stated), leverage, delve, comprehensive, powerful, crucial,
  landscape, journey, "under the hood", "a rich set of".
- Hedge stacks, and bold used as emphasis inside running prose.
- Self-reference to the writing process ("this resolves the question this
  file flagged", "an earlier pass"). Keep history in dated notes, not in
  the body of explanations.

**Do keep.** Formulas, numbers, citations, function names and every fact.
This is a change of language, not of content. Vary sentence length. Prefer
"we" or the imperative to the passive, and say what a function does and
