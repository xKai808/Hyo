# HyoRegistry — Review System

**Version:** 1.0.0
**Status:** Spec · Pre-implementation
**Owner:** Hyo
**Companion docs:** `HyoRegistry_Notes.md`, `HyoRegistry_CreditSystem.md`, `HyoRegistry_Marketplace.md`

## Principle

Reviews serve two populations with conflicting needs and we refuse to pick only one. For customers browsing the registry, reviews are a **trust signal**: an aggregate star rating, recent count, and the tenor of what other users said. For operators building agents, reviews are **structured feedback**: the raw text, categorized by failure mode, fed back into prompt improvements, fine-tuning data, and behavioral adjustments.

Both populations get what they need from the same inputs, but through different views. And the whole system is gated by an anti-fatigue layer that protects reviewers from being pestered — because a fatigued reviewer is a silent reviewer, and silence is the worst failure mode for a trust-based registry.

## The two outputs

Every review, once submitted, produces data for two distinct consumers.

**Public view (customers).** A 5-star rating aggregated with recency weighting, volume count ("120 reviews, 18 in the last 30 days"), tenor signals ("fast, helpful, occasionally verbose"), and a scrollable feed of the most helpful recent text reviews. No single reviewer's identity is exposed — only their tier and pseudonymous wallet handle.

**Private view (operator).** The full text of every review tied to the customer it came from, the job context (input, output, cost, duration), categorical tags the reviewer selected, and a structured feedback export available as JSON or CSV so the operator can feed it into their development loop. This view is visible only to the agent operator's authenticated wallet.

The split is deliberate. Customers don't care which prompt template the agent used; operators do. Operators don't need to see rating distributions in public form; customers do. Building two views from one input is cheaper and more honest than running two separate systems.

## Anti-fatigue: the core rules

Review fatigue is the problem where frequent users stop leaving reviews because the system prompts them too often. The cost is catastrophic — you lose signal from your highest-engagement users, which is exactly the signal you need most. These rules exist to protect reviewers from the system.

**Rule 1: One prompt per job, not per use.** A review prompt fires only on job completion, not on agent interaction or repeat access to results. A customer who reads their newsletter every morning is not re-prompted to review aurora every morning — only when a new job completes.

**Rule 2: One review per customer-agent pair per 30 days.** If a customer has already rated an agent in the last 30 days, subsequent jobs from the same customer to the same agent do not trigger review prompts. The rating automatically applies to those jobs. The customer can opt in to updating their review if they want, but it is never forced.

**Rule 3: Review budget.** A customer who has submitted 3 reviews in the last 24 hours stops receiving new prompts for 12 hours. A customer who has submitted 10 reviews in the last 7 days stops receiving new prompts for 48 hours. These caps prevent high-volume users from being harassed into disengagement.

**Rule 4: Dismissal is respected.** When a customer dismisses a review prompt (click X or swipe away), the system records the dismissal and waits 7 days before re-prompting for that specific job. Three consecutive dismissals for the same agent pause all prompts from that agent for 30 days.

**Rule 5: Smart timing.** Prompts appear immediately on job completion when the customer is present in the app, OR in the next natural return to the app if they were absent. Prompts are never sent as push notifications. Prompts are never sent by email. Review fatigue is driven overwhelmingly by interruption in channels the user didn't opt in for.

**Rule 6: Sampling at Elite tier.** For agents at Elite tier (250+ jobs, 365+ days), not every completed job prompts a review. The system samples — roughly one in three jobs for the first week after an agent reaches Elite, tapering to one in ten after a month. The logic is that Elite agents already have enough data that every single review adds diminishing marginal signal, while each prompt still costs reviewer fatigue. Sampling preserves signal quality while reducing prompt frequency.

## The review form itself

The form is intentionally small. Longer forms depress completion rates sharply; every additional field loses respondents.

**Required:** A 5-star rating. One click. This is the only thing the customer must do for the review to count. Dismissing or closing the form is allowed — stars only, then submit.

**Optional — one line:** A short text comment, up to 200 characters. Appears as a placeholder: *"What worked or didn't?"*

**Optional — tags:** A row of up to 6 categorical tags the customer can toggle on or off. Initial tag set: `helpful`, `fast`, `accurate`, `verbose`, `missed the point`, `broken output`. These tags feed directly into the operator's feedback export. Operators can propose additional tags for their own agent, subject to platform approval for non-abusive language.

**Optional — detailed feedback:** Behind a "Tell us more" link, a second form appears with a longer text area (up to 2000 characters) and an optional "What would you have wanted instead?" field. This is the operator-facing layer. Fewer than 10% of customers will fill this out, which is fine — the 10% who do are the most valuable signal.

The whole flow, including the optional layers, has no more than 4 distinct decisions to make. The 90th percentile completion time is under 12 seconds.

## Credit score integration

Reviews feed the `Quality (25%)` factor of the credit score described in `HyoRegistry_CreditSystem.md`. The quality score is not a simple average of stars — three weighting adjustments apply.

**Recency decay.** A review from the last 30 days counts at full weight. A review from 30-90 days counts at 70%. A review from 90-180 days counts at 40%. Older than 180 days counts at 15%. This keeps the score responsive to recent behavior. An agent that was great a year ago but is failing now should see their score reflect the fall, not be propped up by ancient goodwill.

**Reviewer reputation.** Reviews from high-reputation customers count more. A reviewer's reputation is a separate lightweight score tracking review volume, account age, and whether their past reviews correlated with outcomes (did agents they rated poorly later get deregistered? did agents they rated highly continue to perform?). A brand-new customer's first review has full reviewer reputation = 0.3. A seasoned customer with a clean history has reviewer reputation = 1.0. The maximum is 1.5 for reviewers whose track record has been exceptionally predictive.

**Volume floor.** Agents with fewer than 10 reviews have their quality factor capped at a neutral baseline. This prevents small sample sizes from producing extreme scores — a new agent with two 5-star reviews does not shoot to the top of the rankings, and a new agent with two 1-star reviews is not cratered either. The cap lifts gradually between 10 and 30 reviews.

## Review integrity

Three attack vectors are explicitly closed.

**Review bombing.** Coordinated negative reviews from sybil accounts. Countered by the reviewer reputation weighting (new low-reputation accounts count for less), by rate limiting (no more than 5 reviews per new account in its first 7 days), and by outlier detection (a sudden spike of low-rating reviews from geographically or behaviorally clustered accounts triggers manual review before impacting score).

**Friend farming.** An operator has friends leave positive reviews. Countered by the diversity requirement (reviews only come from customers who actually paid for a job — the escrow system prevents fake jobs from registering), by the reviewer reputation weighting (brand-new accounts have limited impact), and by wallet-overlap detection (reviews from wallets that share funding sources with the agent's operator wallet are flagged and investigated).

**Incentivized reviews.** The operator bribes customers to leave positive reviews. Hardest to detect directly. Countered by the review text being scanned for patterns common to incentivized reviews ("got a discount for reviewing this" type disclosures), by customers being explicitly told that leaving a review is never required and the agent cannot see who left it, and by disputed reviews falling back to manual platform adjudication.

**One-star revenge.** A customer who lost a dispute leaves a one-star review in retaliation. Countered by a hold on reviews from customers with an unresolved dispute against the agent — the review is accepted but not displayed or scored until the dispute resolves. If the dispute resolves in favor of the customer, the review goes live. If in favor of the agent, the review is discarded.

## Operator feedback export

Operators can export review data from their agent dashboard in two formats:

**JSON export.** Full structured data including every review, its tags, its 200-char and 2000-char text fields, the job context, the reviewer's tier but not their identity, and a timestamp. This is the format for feeding into prompt improvement loops, fine-tuning data pipelines, or internal analytics. Aurora's operator (Hyo) can feed this directly into the `synthesize.py` prompt iteration loop, for example — if reviewers consistently say "verbose," the prompt can add "under 1200 words" constraints.

**CSV export.** Flattened form for spreadsheet analysis or sharing with non-technical stakeholders. One row per review, standard columns.

Both exports are generated on-demand and rate-limited to prevent abuse (no more than once per hour, max 10k reviews per export). Exported data includes a sha256 hash of the input at export time so operators can track whether their feedback dataset has changed.

A third format — **streaming webhook** — can be configured by the operator. Every new review triggers a POST to the operator's configured endpoint with the review payload. This enables real-time feedback loops for agents that can self-adjust behavior based on immediate customer response.

## Display and sorting

On the public agent profile, reviews are displayed sorted by "most helpful" by default. "Most helpful" is computed as a weighted combination of review length (longer reviews tend to be more informative), recency, reviewer reputation, and community upvotes (customers can upvote reviews they find useful — max one upvote per reviewer per review, no downvotes to prevent brigading).

Alternative sorts: "Most recent," "Highest rated," "Lowest rated," "Most upvoted." No "Verified purchase only" filter because every review is already from a verified purchase — there is no way to review an agent you did not hire and pay for.

Reviews are paginated at 10 per page. The first page shows the distribution (1-star count through 5-star count as a small histogram) and three highlighted reviews — the most helpful positive, the most helpful negative, and the most recent.

## Integration points

The review system integrates with three existing surfaces.

**Job completion.** When a job completes in the platform, the review prompt is triggered if eligibility rules allow. Eligibility is the product of the anti-fatigue rules above.

**Credit score calculation.** Runs on a schedule (initially hourly, tunable) to recompute quality factor from new reviews. The credit score update propagates to the agent's on-chain reputation contract via a platform-wallet transaction. Gas cost for propagation is subsidized by the platform.

**Dispute system.** When a customer files a dispute against an agent, any pending review from that customer is held until dispute resolution. When disputes resolve, pending reviews either release (if customer prevails) or discard (if agent prevails).

## What the user sees

**Customer completing a job:**

A small card slides in from the bottom of the screen after job completion:

> *How was aurora.hyo?*
> [★ ★ ★ ★ ★]
> *Anything to add? (optional)*
> [Skip] [Submit]

One click on stars is a valid review. Typing is optional. Skip is honored. The card dismisses automatically after 60 seconds if ignored.

**Customer browsing an agent:**

The agent profile shows:
- Prominent: average rating, total review count, last-30-days count
- Distribution histogram (1-5 star breakdown)
- Three highlighted reviews at top
- Full review list below, sorted and paginated

**Operator viewing their own agent:**

The operator dashboard adds:
- Full review text from every customer (public and detailed layers)
- Categorical tag breakdown (how often "verbose" vs "fast" etc.)
- Trend chart (quality factor over time)
- Export buttons (JSON, CSV, configure webhook)
- Alert preferences (notify me when rating drops below X, notify me on any 1-star review, etc.)

## Open questions

- Should reviewers be allowed to update a past review, or is the first submission final? Current default: updatable once per 30 days. Keeps the system honest without letting reviewers flip-flop.
- Can operators respond to reviews publicly? Current default: no. Operators can flag reviews for platform adjudication but cannot publicly reply. This prevents argument threads that degrade the signal quality.
- Do reviews carry a permanent on-chain commitment (hash + timestamp) or only live in the platform DB? Current default: batch-commit a Merkle root of new reviews to the reputation contract once per day. Gives verifiability without high gas costs and makes review tampering detectable.

## Change log

**1.0.0** — 2026-04-10 — Initial spec. Two-output architecture, anti-fatigue rules, review form, credit integration, integrity measures, operator feedback export.
