# Fork notes

Fork of [liustack/modsearch](https://github.com/liustack/modsearch) **v5.10.5** (MIT, © Leon Liu).
No pull request upstream. This file records what changed, so a later upstream release can be
re-synced by re-applying the diff below rather than by hand-editing a diverged tree.

## What this fork adds

One engine: **`perplexity`** — Perplexity Fast Search through the Nous Tool Gateway
(`https://perplexity-gateway.nousresearch.com`), authenticated with a **Nous Portal OAuth bearer
token instead of a Perplexity API key**.

It is first in the search role preference, with Firecrawl immediately behind it as the keyless
fallback, so search still answers when the gateway is unreachable or the token has expired.

## Files changed (everything else is byte-identical to upstream)

| File | Δ | Change |
|---|---|---|
| `dist/main.js` | +115 | `perplexityProvider` + `executePerplexitySearch`; registry entries in `ENGINES`; `perplexity` first in `ROLE_PREFERENCE.search`; `perplexity` in `ENV_BINDINGS` |
| `dsh/index.js` | +56 | Portal-token resolver installed in `apply()`; `perplexityEnv()` merged into the CLI child env; `perplexity`/`pplx` added to `CARD_ENGINES`, `KEYED_ENGINES`, `ENGINE_ENV_BINDINGS`, `ENGINE_ALIASES`; doctor hints point at the bundled CLI |
| `dsh/client.js` | 2 lines | **`id` and `PACKAGE_NAME` must be `@local/modsearch-nous`.** See invariant 6 — a stale value here is what broke plugin mounting. |
| `skills/modsearch/scripts/run.sh`, `run.ps1` | +~25 | bundled-CLI resolution path, tried before any network path |
| `skills/modsearch/SKILL.md`, `references/runtime*.md` | — | launcher order documents the bundled CLI first; network paths marked last resort |
| `scripts/check-fork-identity.sh` | new | guard for invariants 6 and 7 |
| `package.json` | — | renamed `@local/modsearch-nous`, version suffix `-nous.1`, description/keywords |
| `cordis.patch.yml` | — | plugin row points at `@local/modsearch-nous` and passes `perplexityCredential` |
| `README.md` | — | fork banner and attribution |

Unchanged from upstream: `dsh/*-schema.json`, `dsh/spawnHidden.js`, `LICENSE`, `docs/`.

## Non-obvious invariants — do not "simplify" these away

1. **`search_type: "fast"` is mandatory.** Perplexity meters the default search meter
   separately and a Portal subscription is not entitled to it: the default answers
   `409 BILLING_ERROR` / `unsupported_pricing_meter`. Only `fast` is free. The field is pinned
   inside `executePerplexitySearch` so no configuration can move the request onto a billed route.
   (Measured on this account: no field → 409, `"fast"` → 200, `"web"` → 409.)
2. **`POST /search` is the only allowlisted path.** `/chat/completions`, `/v1/chat/completions`,
   `/v1/search` and `/extract` all return `400 not allowlisted through passthrough mode`. This is
   why the engine does not reuse upstream's `baseURL + /chat/completions` pattern, and why it
   declares `roles: ["search"]` only — page fetch stays with Firecrawl / agy / local.
3. **`isAvailable` must stay cheap and offline.** A readiness check that performs network I/O
   would make `doctor` slow and could cost a billed request.
4. **The token is passed only in the child environment.** `dsh/index.js` resolves the
   `NOUS_API_KEY` credential per call and merges it into the spawned CLI's env. It never reaches a
   config file, an argv entry, or a log. An inherited `PERPLEXITY_API_KEY` wins, so standalone CLI
   runs and containers keep working.
5. **The credential is resolved per call, never cached.** The Portal JWT is short-lived; the auth
   bridge rewrites the reference ahead of expiry and the next search picks it up without a restart.
6. **`dsh/client.js`'s `id` and `PACKAGE_NAME` must equal the `package.json` name.** dsh mounts a
   plugin by matching the id the browser half registers against the installed package name. When
   they differ the row is refused with nothing but a generic `failed to import` — while the CLI, the
   engines, and the credential all keep working, so behavioural tests cannot see it. It already
   broke this fork once and, because the profile loads many plugins in one batch, took that whole
   group down with it.
7. **No launcher may fetch this fork from npm.** It is local-only and unpublished, so
   `npx @liustack/modsearch@<v>` would install the NON-fork (silently losing the `perplexity` engine)
   and `npx @local/modsearch-nous` would 404. The bundled `dist/main.js` is therefore tried first.

Invariants 6 and 7 are enforced by `scripts/check-fork-identity.sh`; run it after any rename.

## Verifying a change

```sh
bash scripts/check-fork-identity.sh            # identity invariants; must exit 0
node --check dist/main.js && node --check dsh/index.js
node dist/main.js doctor                     # perplexity listed first under search
PERPLEXITY_API_KEY=<token> node dist/main.js -q "test query" --source web
bash skills/modsearch/scripts/run.sh where    # must print "bundled", never npx
```

Expected: `engine: perplexity`. With no token, or with a rejected token, the chain must fall
through to `firecrawl` — that fallback is the reason this engine is safe to lead with.