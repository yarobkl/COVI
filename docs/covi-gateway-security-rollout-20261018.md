# COVI — Security gate for public orders (18 October 2026)

**Decision: DO NOT DEPLOY without owner approval and a verified rollback plan.**

Scope: a narrow security patch based on the deployed branch
`claude/caisse-multi-caissiers` at commit
`2e48893ad0d5171c51c6f316814961260a4a218c`.
Proposed PR #45 is a **draft**. The experimental category-stock PR #22
must never be merged wholesale into this branch.

## Findings corrected in code (not deployed)

1. **Fail-open feature switch**: the existing Edge entrypoint accepted public
   requests when `COVI_GATEWAY_ENABLED` was unset. New entrypoint requires the
   *literal* value `true`; all other values cause HTTP 503 before any RPC.
2. **Shared secret derivation**: an unset `COVI_GATEWAY_PEPPER` previously
   derived the quota HMAC key from `SUPABASE_SERVICE_ROLE_KEY`. The new code
   requires a separate secret of at least 32 characters. This separates quota
   fingerprints from the database service key's life cycle.
3. **Turnstile action binding**: challenge verification previously accepted a
   token with no `action`. It now requires `action === 'covi_order'`.
   The deployed frontend `TurnstileChallenge.tsx` already renders this
   explicit action, so the legitimate submission path has the correct action.

## Mandatory production compatibility checks before authorizing deployment

- In **Supabase Edge Functions → Secrets**, verify whether
  `COVI_GATEWAY_ENABLED` is currently configured and exactly `true`.
  If it is absent, the new patch will intentionally close the public order
  channel after deployment. This is safe for integrity but is a business outage.
- Provision a fresh, cryptographically random `COVI_GATEWAY_PEPPER`
  independently, in the Edge secret store. Do not paste it into GitHub, this
  document, the frontend, chats, or query strings.
- Confirm `COVI_TURNSTILE_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` and
  `COVI_PUBLIC_ORIGIN` are correctly configured without displaying secrets.
- Verify real Turnstile tokens for current official/allowed hosts include the
  exact action `covi_order`, including after domain changes.
- Test catalog, order submission and tracking through the hosted Edge gateway.
  Check that missing toggles/secrets result in 503 and do not call database RPCs.
- Review and document emergency rollback, public order channel disable switch,
  and the impact of rotating the quota pepper (resets prior rate-limit digests).
- Preserve the existing manual cashier/PIN workflow and the DA « Le Cahier ».

## Residual risks — NO-GO

- `Origin` is a browser policy signal, not reliable user authentication.
  Quotas, Turnstile and private SQL permissions must remain effective even if
  non-browser clients spoof `Origin`.
- Shared management account and PIN attribution do not isolate management
  privileges when credentials are shared.
- Real Supabase Auth/PostgREST and hosted network boundary need independent
  security verification. Passing local CI does not establish deployment safety.
- The experimental branch diverges from production; do not migrate its schemas
  or integrate its separate checkout without a full compatibility review.
- Payment receipt must always reflect the cashier's manual confirmation of
  funds actually received, not an automatically asserted provider verification.

No migration, deploy, secret change, auth change or production mutation is
performed by this PR. Explicit approval is mandatory before applying it.
