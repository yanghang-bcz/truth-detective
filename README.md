# Truth Detective · Stillwater Corner

**An AI-assisted reasoning game about how strongly evidence actually supports an online claim.**

[中文 README →](README_中文.md)

You are a detective in a small 3D neighborhood. A viral clip shows a young woman
apparently lashing out at an elderly man on a subway platform. Your job is not to
decide whether the clip is "real" — it is. Your job is to decide **how much of the
story it can actually carry**, claim by claim, and to notice the exact moment your
certainty outruns your evidence.

Built with Godot 4.5 · AI layer powered by DeepSeek (optional — the game never
depends on it)

---

## Problem

Most online harm doesn't come from outright fabrication. It comes from

> **partial truth + missing context + overinterpretation.**

A 14-second video can be completely authentic and still mislead — because of what
happened before the recording started, what the caption adds, and how far viewers
generalize from one stranger's worst moment.

Media-literacy tools mostly answer *"is this true?"*. The harder, more useful
question is *"what does this evidence actually entitle me to say?"*

## Product

Case 001 is a complete vertical slice of that loop:

```
3D neighborhood
  → subway-entrance trigger
  → 14-second covert clip
  → Initial Judgment (claim + confidence)
  → Investigation Board: spend points to open 8 evidence cards
  → classify what each card does / does not prove
  → consult the AI Analyst (limited uses)
  → revise your judgment as evidence accumulates
  → Final Judgment across a 4-rung claim ladder
  → Reasoning Debrief: timeline of how your reading changed
```

The claim ladder is the heart of the design:

| Rung | Claim | What players discover |
|---|---|---|
| A | She used aggressive language. | The record can support this. |
| B | She attacked *without provocation*. | The viral clip alone can't carry this. |
| C | This shows her character. | One moment doesn't generalize to a person. |
| D | Young people no longer respect elders. | One person doesn't generalize to a generation. |

Players routinely accept A and then watch themselves fail to justify B, C, and D
with the same evidence. That gap **is** the game.

## Why AI?

The AI is not a fact-checker and not a detective. It is a **Reasoning Coach** —
a layer sandwiched between Evidence and Judgment. It never answers *"what's the
truth?"*; it only ever answers *"how far does your current evidence let you go?"*

Four structured actions, no free-form chat box:

- **Explain this evidence** — what does this card actually establish?
- **What does it NOT prove?** — the inference boundary of a single card.
- **Challenge my judgment** — stress-tests the weakest link between your unlocked
  evidence and your confidence. It is instructed to make your reasoning *more
  precise, not more contrary*: if the evidence genuinely supports your direction,
  it questions your confidence level instead of manufacturing disagreement.
- **What am I missing?** — points at the *category* of information you haven't
  looked at, never at a specific locked card.

Consultations cost **Analyst Tokens — 3 per case**. If AI were free, the optimal
strategy would be "ask four questions after every card" and the player would stop
thinking. Deciding *when* AI help is worth a token is itself part of the literacy
being trained.

## AI Safety Architecture

The most important engineering rule of the project:

> **The LLM is not the source of truth. The case database is.**

```
                 Case Database (data/case_001.json)
                          │
                          ▼
                      CaseState            ◄── only evidence the player
                          │                    has actually unlocked
              ┌───────────┴───────────┐
              ▼                       ▼
     Unlocked Evidence        Player Judgment + Confidence
              └───────────┬───────────┘
                          ▼
              Safe Context Builder      ◄── whitelist, not blacklist:
                          │                  answer fields (kind_answer,
                          │                  verdict, decisive_evidence, …)
                          │                  can never enter the request
                          ▼
                    DeepSeek API        ◄── 10 s timeout, ≤400 tokens,
                          │                  explicit output language
                          ▼
               Response Validator       ◄── blocks: locked-evidence leaks,
                          │                  hallucinated evidence IDs,
                          │                  direct answers
                   ┌──────┴──────┐
                   ▼             ▼
                 Safe         Unsafe ──► silent fallback to the
                   │              offline rules engine, no token consumed
                   ▼
                 Player
```

Concretely:

- **Whitelist context.** The model receives only fields the player can already
  see on screen. It is never told how many other cards exist — even *"5 more
  remain"* would leak information structure.
- **Prompt-side hard rules.** No inventing facts, no referencing locked cards,
  no stating the final answer, two short paragraphs max.
- **A validator before display.** If a reply cites a locked or nonexistent
  evidence ID, or hands over the answer ("the correct answer is…"), it is
  withheld and replaced by the offline engine's reply. The player never sees
  `AI ERROR CODE 04` — people aren't here to debug an API.
- **Failures never cost the player.** No key, timeout, HTTP error, or a blocked
  reply → the game falls back to a local rules engine that reads the same
  hand-written case data, and the Analyst Token is refunded. The game is fully
  playable with no key at all — it never lives on the LLM.
- **Cache.** Identical question (same evidence set + judgment + action) returns
  the cached reply without spending another token.

## Running locally

Requirements: Godot 4.5.x (Forward+). No other dependencies.

```bash
git clone https://github.com/yanghang-bcz/truth-detective.git
# open project.godot in Godot and press F5
```

Controls: WASD / arrows to walk, Shift to run, `E` at the subway entrance to
open the case. Language toggle (EN / 中文) is in the case screen's top bar.

### Enabling the AI Analyst

The game works end-to-end without a key. To switch the Analyst from the offline
rules engine to DeepSeek, either:

```bash
export DEEPSEEK_API_KEY=sk-...
```

or create `config/local.env` (git-ignored — see `config/local.env.example`):

```
DEEPSEEK_API_KEY=sk-...
```

The key is read from those two places only, in that order. It is never written
into the repository. The console states which engine is active at startup:

```
[AiCoach] AI_PROVIDER=deepseek model=deepseek-chat
[AiCoach] AI_PROVIDER=fallback reason=no_key
```

## Verification

Three automated suites guard the things that break silently:

```bash
./godot.sh --test                              # all of the below
# ├─ tools/test_player.gd          12 physics/gameplay checks
# ├─ tools/validate_scene.gd       scene integrity (merge batch counts, owners)
# ├─ tools/test_case_trigger.tscn  25-assertion smoke test:
# │                                street → [E] → case → close → back to street
# └─ tools/test_ai.tscn            47 checks: locked-evidence never appears in
#                                  prompts, validator blocks leaks/hallucinated
#                                  IDs/direct answers, no-key degradation,
#                                  timeout/4xx/5xx don't crash and don't
#                                  consume tokens, cache & token exhaustion
```

Performance is benchmarked, not eyeballed (on a fanless 8 GB MacBook Air M3):

| Metric | Before | Now |
|---|---|---|
| Draw calls (street) | 3,950 | 302 |
| Median frame (street) | 7.52 ms | 6.32 ms |
| Median frame (case screen) | 6.49 ms | 2.23 ms |

The case screen is a full-screen opaque layer, but Godot keeps rendering the 3D
street beneath it — the game now suspends world rendering while a case is open.
`tools/bench_case.tscn` keeps a live A/B comparison so deleting that optimization
fails loudly.

## Repository layout

```
data/             case content, one JSON per language — all writing lives here
scripts/ai/       client · safe context · prompt builder · validator · coach
scripts/phases/   intro → board → final → debrief (UI is 100% script-built)
scripts/ui/       design system, analyst panel, video still, judgment rows
tools/            scene builders, test suites, benchmarks, screenshot rigs
blender/          the detective is generated by build_detective.py, not hand-made
```

Two conventions worth knowing before editing: scenes are **generated by scripts**
(`tools/build_*.gd`, run `./godot.sh --rebuild`) — never hand-edit `.tscn` files;
and all player-facing text lives in `data/*.json` + `scripts/locale.gd`, never
hard-coded in UI code.

## What's next

- **User study (5–8 players, with/without AI).** The headline metric is
  *AI Override Rate*: after the Analyst challenges a judgment, does the player
  go investigate more — or just copy the AI? The first outcome is the product
  working; the second is the product failing.
- **Case 002** ("90% of users improved") — a statistics/commercial-claim case,
  to prove the system generalizes beyond viral-video incidents. Only after
  Case 001 has been through a full test-and-iterate loop.

## Credits

Character base: Kenney Blocky Characters 2.0 (CC0), heavily modified — see
`ASSET_CREDITS.md`. All case content is fictional; any resemblance to real
events is the point of the genre, not a reference.
