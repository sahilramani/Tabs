# Sample statements

Synthetic, privacy-safe statement fixtures. Every bank, name, account number,
and amount is fictional. They ship inside the app so anyone can try the
detector without feeding it a real bank statement — the import sheet's "Try
sample statements" row reads them, and they can be previewed before import.

`generate-statements.py` writes the HTML and renders each month to a
text-selectable PDF through headless Chrome. PDFKit needs real text, so a
scanned image would not work. Output lands in `Tabs/SampleStatements/`, which
the app target picks up automatically.

```sh
./samples/generate-statements.py    # requires Google Chrome
```

## Why four months

`RecurringChargeDetector` needs at least three sightings of a charge before it
will call it recurring, so a single statement demonstrates nothing. Four
consecutive months (March–June 2026) put the regular subscriptions safely over
that line.

The data is shaped to exercise the interesting paths, not just the happy one:

- Eight subscriptions recur on a fixed day and amount, so they detect cleanly.
- Hulu rises from $17.99 to $18.99 halfway through, which is what a real price
  change looks like to the clusterer.
- A gas station recurs on a regular cadence with a different amount every time,
  so it surfaces deselected as "Amounts vary — looks one-off".
- An annual Amazon Prime charge appears once and stays a single-charge
  candidate, since four months can't establish a yearly cadence.
- Groceries, restaurants, and rides change month to month and should be
  rejected outright.

Edit the tables at the top of `generate-statements.py` and re-run it to change
any of that. Commit the regenerated PDFs — they are app resources, and CI has
no Chrome to rebuild them.
