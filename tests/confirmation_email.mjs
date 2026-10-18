import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const config = readFileSync('supabase/config.toml', 'utf8')
const html = readFileSync('supabase/templates/confirmation.html', 'utf8')

test('COVI local Auth enforces confirmation without weakening deployed Auth settings', () => {
  assert.match(config, /\[auth\.email\]\s*enable_confirmations\s*=\s*true/)
  assert.match(config, /\[auth\.email\.template\.confirmation\]/)
  assert.match(config, /subject = "COVI — Confirmez votre compte et démarrez votre activité"/)
  assert.match(config, /content_path = "\.\/supabase\/templates\/confirmation\.html"/)
})

test('confirmation email has valid clickable Supabase verification link', () => {
  assert.match(html, /<html lang="fr">/)
  assert.match(html, /Confirmer mon adresse e-mail/)
  assert.match(html, /\.Data\.business_name/)
  assert.match(html, /\.Data\.business_kind/)
  assert.equal((html.match(/href="{{ \.ConfirmationURL }}"/g) ?? []).length, 2)
  assert.doesNotMatch(html, /href="https:\/\/covi-snowy\.vercel\.app[^"]*confirm/)
  assert.doesNotMatch(html, /service_role|SUPABASE_SERVICE_ROLE_KEY|RESEND_API_KEY/i)
})
