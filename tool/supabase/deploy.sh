#!/usr/bin/env bash
# Deploys the Buzz Masters backend to ONE Supabase project, after checks.
#
#   npx supabase@2.54.11 login            # once, official browser sign-in
#   tool/supabase/deploy.sh <project-ref>  # e.g. abcdefghijklmnopqrst
#
# What it does, in order, stopping on the first failure:
#   1. refuses known projects of other apps, and asks you to confirm the ref
#   2. runs the backend test suite on real PostgreSQL (PGlite)
#   3. links the repo to the project and shows the pending migrations
#   4. applies them (supabase db push: additive, never resets data)
#   5. pushes auth settings from supabase/config.toml (the CLI shows the
#      diff and asks before changing anything)
#   6. deploys the four Edge Functions with the right JWT settings
# Secrets are never passed on the command line: set them in the dashboard
# (Edge Functions → Secrets) or with `supabase secrets set` yourself.
set -euo pipefail

REF="${1:-}"
CLI=(npx -y supabase@2.54.11)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Projects that belong to other apps and must never receive this schema.
FORBIDDEN=(azafjqjbvklajsplykyv)

if [[ ! "$REF" =~ ^[a-z]{20}$ ]]; then
  echo "usage: $0 <20-letter Supabase project ref>" >&2
  exit 2
fi
for f in "${FORBIDDEN[@]}"; do
  if [[ "$REF" == "$f" ]]; then
    echo "refusing: $REF belongs to another application" >&2
    exit 3
  fi
done

echo "Projects visible to this login:"
"${CLI[@]}" projects list
read -r -p "Deploy Buzz Masters to project $REF? Type the ref again to confirm: " again
[[ "$again" == "$REF" ]] || { echo "not confirmed"; exit 4; }

echo "== backend tests"
(cd "$ROOT/supabase/tests" && npm install --silent && npm test)

cd "$ROOT"
echo "== link"
"${CLI[@]}" link --project-ref "$REF"

echo "== pending migrations"
"${CLI[@]}" migration list
"${CLI[@]}" db push --dry-run
read -r -p "Apply these migrations? [y/N] " yes
[[ "$yes" == "y" || "$yes" == "Y" ]] || { echo "stopped before applying"; exit 5; }
"${CLI[@]}" db push

echo "== auth settings from supabase/config.toml"
echo "   (anonymous sign-ins, manual linking, the app's login redirect)"
"${CLI[@]}" config push

echo "== edge functions"
"${CLI[@]}" functions deploy revenuecat-webhook --no-verify-jwt
"${CLI[@]}" functions deploy admob-ssv --no-verify-jwt
"${CLI[@]}" functions deploy revenuecat-sync
"${CLI[@]}" functions deploy delete-account

cat <<MSG

Done. Still to do in the dashboard (they need your decisions or secrets):
  * Authentication → Providers: Apple and Google (need your keys)
  * Edge Functions → Secrets: REVENUECAT_WEBHOOK_SECRET,
      REVENUECAT_SECRET_API_KEY, AD_REWARD_COINS, AD_REWARD_MAX_PER_DAY
  * Advisors: run Security and Performance and review the results
MSG
