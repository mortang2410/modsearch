#!/usr/bin/env bash
# Guard the fork's identity invariants.
#
# WHY THIS EXISTS: the fork renamed its npm package but initially left two stale
# references to the upstream name in code that decides whether the plugin loads at
# all. dsh requires the client-half id to equal the installed package name, so a
# mismatch is silent: the CLI keeps working, only the plugin refuses to mount, and
# because the profile batch loads many plugins together one bad id takes the whole
# group down. Nothing in dsh reports this as its own error.
#
# Run after ANY rename or re-sync:
#     bash scripts/check-fork-identity.sh
#
# Exits non-zero with every problem listed, so it is safe as a pre-commit or CI gate.
set -uo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PKG_NAME="$(node -e "process.stdout.write(require('./package.json').name)" 2>/dev/null)"
UPSTREAM="@liustack/modsearch"
fail=0

note() { printf '  %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fail=1; }

printf 'fork identity check (%s)\n' "${PKG_NAME:-unknown}"

# 1. The client half must claim the installed package name. This is the invariant
#    whose violation broke plugin mounting.
if [[ -z "$PKG_NAME" ]]; then
  bad "cannot read the package name from package.json"
else
  for loc in "dsh/client.js:17" "dsh/client.js:32"; do
    file="${loc%%:*}"; line="${loc##*:}"
    if [[ ! -f "$file" ]]; then
      bad "$loc: file missing"
      continue
    fi
    actual="$(sed -n "${line}p" "$file")"
    if [[ "$actual" != *"$PKG_NAME"* ]]; then
      bad "$loc does not name the package"
      note "expected $PKG_NAME"
      note "found:    ${actual##+([[:space:]])}"
      note "dsh mounts a plugin by matching this id against the installed package"
      note "name; when they differ the row is refused and only a generic"
      note "'failed to import' is reported."
    fi
  done
fi

# 2. The cordis patch must mount the fork, not upstream.
if ! grep -qF "name: '$PKG_NAME'" cordis.patch.yml 2>/dev/null; then
  bad "cordis.patch.yml does not mount $PKG_NAME"
fi

# 3. No launcher may fetch the fork from npm: it is unpublished, so that path
#    either 404s or silently installs the NON-fork and drops the perplexity engine.
for launcher in skills/modsearch/scripts/run.sh skills/modsearch/scripts/run.ps1; do
  [[ -f "$launcher" ]] || continue
  if grep -qF "$PKG_NAME@" "$launcher"; then
    bad "$launcher installs $PKG_NAME from npm"
    note "the fork is local-only and unpublished; use the bundled CLI instead"
  fi
done

# 4. Code that would EXECUTE the upstream package as its PREFERRED path silently
#    drops this fork's engine while appearing to work. Documentation is not code:
#    the skill and runtime references describe the last-resort network paths on
#    purpose, so only a launcher whose resolution actually prefers upstream counts.
#    A mention inside a comment is excluded too — those explain the hazard.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  bad "executable reference to the upstream package would bypass this fork"
  note "  ${hit#"$ROOT"/}"
done < <(
  for launcher in skills/modsearch/scripts/run.sh skills/modsearch/scripts/run.ps1; do
    [[ -f "$ROOT/$launcher" ]] || continue
    # The package variable itself, or a bundled-first guard, is what matters.
    grep -nE "^\s*(PKG|Package)\s*=|npx\)\s*exec|exec npx|bunx\)\s*exec" \
      "$ROOT/$launcher" 2>/dev/null | grep -F "$UPSTREAM" \
      | sed "s|^$ROOT/||"
  done
)

if [[ "$fail" == 0 ]]; then
  printf 'OK: package name, client id, patch row, and launchers all agree.\n'
fi
exit "$fail"