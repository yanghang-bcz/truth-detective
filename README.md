# Truth Detective · Stillwater Corner

**An AI-assisted reasoning game about how strongly evidence actually supports an online claim.**

[中文 README →](README_中文.md)

> **▶ Play in your browser: [truth-detective-07655.app.workbuddy.host](https://truth-detective-07655.app.workbuddy.host/)**
> The full Case 001, no install. **The API key is not in this front end** — the
> web build routes Analyst requests through a same-origin backend proxy (see
> [Web export & deployment](#web-export--deployment)), so the key only ever lives
> server-side. With no key configured there, the Analyst falls back to its
> offline rules engine and the game still plays start to finish.

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

### Web export & deployment

A web build is not "export a static bundle and ship it" — **the DeepSeek key must
never reach the browser.** So the web version is two pieces: the Godot static
build plus a same-origin Node backend.

```
browser  ──POST /api/analyst──▶  server.js  ──Bearer key──▶  DeepSeek
   ▲                                │
   └──── index.html/pck/wasm ───────┘   (static hosting, no key anywhere)
```

One command does the export, the assembly and the server-side key:

```bash
./web_build.sh          # output lands in build/web
./web_build.sh --serve  # also serves it locally on 127.0.0.1:8080
```

`server/server.js` has zero dependencies (node built-ins only) and does three
jobs:

1. **Static hosting** for the Godot build, while denying `server.js` /
   `deepseek.key` / `case/` and any path traversal — the key file sits in the
   same directory but is **not reachable over HTTP**.
2. **Proxying** `/api/analyst`. The key is read only from `DEEPSEEK_API_KEY` or a
   sibling `deepseek.key` file; it is never returned to the front end and never
   logged.
3. **Pinning its purpose.** The request body must carry the family's own system
   prompt marker, otherwise it's a 400. That stops anyone from using this proxy
   as a free general-purpose LLM.

Plus limits: 16 KB body, 4000-char system, 8000-char user, 12 requests per IP per
300 s, 400/day globally, 8.5 s upstream timeout. Before returning, the server
re-runs the same "locked evidence ID / direct answer" checks the client validator
uses.

On web the front end switches to proxy mode automatically and says so:

```
[AiCoach] AI_PROVIDER=proxy endpoint=https://…/api/analyst (same-origin proxy, the front end holds no key)
```

Known web-build difference: the neighborhood's fog shader is Forward+-only, so
fog simply doesn't render under WebGL2. Everything else is identical. The Web
preset deliberately disables thread support so the build runs on any plain static
host (no COOP/COEP headers needed), and its exclude filter keeps
`config/local.env` — i.e. **your API key can never end up inside the published
`.pck`**.

### Live deployment

The public playable instance:

| | |
|---|---|
| URL | https://truth-detective-07655.app.workbuddy.host/ |
| Shape | one Node port — Godot static output + same-origin `/api/analyst` proxy |
| Key lives | server-side env var / `deepseek.key` only; never in the page or `.pck` |

The server has no third-party dependencies (`node:http`, `node:https`,
`node:fs`, `node:path`, `node:crypto` only) — the repo has no `node_modules`.

**Cost.** A full Case 001 normally costs 1–3 model calls (3 Analyst consults
per case). Two extra gates sit server-side: 12 requests per IP per 300 s, and a
global 400/day cap. **Hitting either gate degrades the Analyst to the offline
rules engine instead of erroring** — players never see a broken screen, and the
bill can't run away.

**Ops.**

| To change | Do this |
|---|---|
| API key | set `DEEPSEEK_API_KEY` on the server (or `deepseek.key` beside it), restart |
| Game content | `./web_build.sh`, then redeploy |
| Backend status | `GET /api/health` → `{ok, key_configured, evidence_ids, daily_limit, day_count}` (never echoes the key) |
| Turn AI off entirely | just don't set a key — the Analyst falls back to the offline engine, gameplay and the final verdict are unaffected |
| Probe a deployed backend | `BASE=https://… node server/test_proxy.mjs` |

All quota and rate-limit knobs live in the constants block at the top of
`server/server.js` (`BODY_LIMIT_BYTES`, `SYSTEM_MAX`, `USER_MAX`, `IP_WINDOW_MS`,
`IP_MAX`, `DAILY_LIMIT`, `UPSTREAM_TIMEOUT_MS`) and take effect server-side
without any front-end change.

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
into the repository. The desktop build talks to DeepSeek directly when it has its
own key; you can also force the desktop build through the proxy to exercise the
backend:

```bash
TD_AI_PROXY=1 ./godot.sh --run
```

The console states which engine is active at startup:

```
[AiCoach] AI_PROVIDER=deepseek model=deepseek-chat
[AiCoach] AI_PROVIDER=proxy endpoint=…
[AiCoach] AI_PROVIDER=fallback reason=no_key
```

## Verification

Four automated suites guard the things that break silently:

```bash
./godot.sh --test                              # all of the below
# ├─ tools/test_player.gd             12 physics/gameplay checks
# ├─ tools/test_input_map.gd          11 real-input-path checks:
# │                                    key event → InputMap → Input.get_vector → movement
# ├─ tools/test_metro_reachability.gd  can the player actually *walk* from spawn into the trigger?
# ├─ tools/validate_scene.gd          scene integrity (merge batch counts, owners)
# ├─ tools/test_case_trigger.tscn     25-assertion smoke test:
# │                                    street → [E] → case → close → back to street
# └─ tools/test_ai.tscn               47 checks: locked-evidence never appears in
#                                      prompts, validator blocks leaks/hallucinated
#                                      IDs/direct answers, no-key degradation,
#                                      timeout/4xx/5xx don't crash and don't
#                                      consume tokens, cache & token exhaustion
```

The last two cover two "all-green but the game is dead" blind spots:

- `test_player` drives the player through the `automated + test_input` back door,
  so it cannot prove that *a real keypress moves the character*. If action
  registration, physical-key mapping or the Input singleton breaks, every
  existing test still passes while the player just stands there — which is
  exactly where the web build fails first.
- `test_case_trigger` **teleports** the player into the trigger
  (`player.global_position = center`), so "can the player walk to the subway
  entrance?" was never verified. Change the spawn point, a collider or the street
  layout and the whole game can be unplayable while every other test stays green.

The backend has its own security suite. The client's three layers only constrain
requests the game itself makes — they do nothing about someone curling the
endpoint directly, which is what this file tests:

```bash
./web_build.sh --serve &          # one terminal
node server/test_proxy.mjs        # another
# covers: key unreachable over HTTP, server.js/package.json not downloadable,
#         path traversal, index.wasm MIME, a general-purpose prompt disguised
#         as an Analyst request → 400, oversized body → 413, a real DeepSeek
#         round trip, optional rate-limit and quota checks
# env: LIVE=0 skips the live model call; RATELIMIT=1 adds the rate-limit test
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

### Public end-to-end acceptance

"Exported successfully" is not "playable". Before going public we walked the
whole of Case 001 in a real browser against the **public URL**, keeping console
and screen evidence at every step:

| Check | Result |
|---|---|
| Open the link, land in the game | ✅ no Godot install, no API key |
| Walk to the metro entrance, press `[E]` | ✅ |
| File E01 / E04 / E08 on the evidence board | ✅ 3 / 8 opened, 6 / 10 points spent |
| Analyst answers | ✅ `source=ai ok=true`, content strictly tied to unlocked evidence |
| All four claims judged and submitted | ✅ A supported / B unsupported / C not enough evidence / D unsupported |
| Debrief rendered | ✅ three reasoning patterns STRONG |
| Key unreachable over HTTP | ✅ `/deepseek.key`, `/server.js` both 404 |
| Backend safety suite against production | ✅ 17 / 17, including one live DeepSeek round trip |

> Six screenshots live in [`docs/release/`](docs/release/): public case opened →
> evidence board → live Analyst answer → final judgment → debrief.

```
[AiCoach] AI_PROVIDER=proxy endpoint=https://…/api/analyst（同域代理，前端不持有密钥）
[AiCoach] -> deepseek action=explain claim=B target=E08 unlocked=3
[AiCoach] <- source=ai action=explain ok=true tokens_left=2 failure= blocked=
```

That `source=ai` is the whole point: it takes a different code path from
`fallback`. Model-generated prose actually showing up on the page means the
**server-side key, the same-origin proxy, the timeout and the output validator —
the entire chain — work on the public internet.**

The `test_case_trigger` blind spot is covered too: `tools/test_metro_reachability.gd`
now *greedily walks* from the real spawn point into the trigger zone, so moving
the spawn point or reworking the street layout fails immediately instead of
silently shipping a game nobody can start.

## Repository layout

```
data/             case content, one JSON per language — all writing lives here
scripts/ai/       client · safe context · prompt builder · validator · coach
scripts/phases/   intro → board → final → debrief (UI is 100% script-built)
scripts/ui/       design system, analyst panel, video still, judgment rows
server/           web backend: static hosting + /api/analyst proxy + security suite
tools/            scene builders, test suites, benchmarks, screenshot rigs
blender/          the detective is generated by build_detective.py, not hand-made
godot.sh          desktop entry: run / rebuild / tests / bench
web_build.sh      web entry: export + assemble backend + write server-side key
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
