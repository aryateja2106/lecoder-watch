---
status: draft            # draft | accepted | in-progress | shipped | closed
owner: Arya
source: conversation     # conversation | review | monitor | security-scan | customer
date: YYYY-MM-DD
---

# Intent: <one line, in the words you would use to a customer>

## Problem

What hurts today, for whom, and one concrete example of it happening. If you have a
screenshot or a message from a customer, name the file or paste the sentence.

## Proposed outcome

What is true when this is done. Describe the result, not the implementation. "A friend
can install the app from a link in under two minutes" is an outcome; "add a QR code
screen" is an implementation.

## Affected users and systems

Which of these change: Apple Watch app · iPhone app · Mac menu-bar app · daemon (`meshd`)
· `mesh` command line · installer · landing site · documentation · other machines in the
fleet (Pi, Jetson, Linux boxes). Who uses the changed part.

## Constraints

Money, time, and the rules that already exist: local-first (nothing of the user's leaves
their machines), no account system, no cloud relay, App Review rules, security (tokens,
pairing), and anything that must not change for existing installs.

## Open questions

The things only you can answer, or that nobody knows yet. Each one is a line an agent can
ask you in an interview. Leave them here; they are more useful than a guessed answer.
