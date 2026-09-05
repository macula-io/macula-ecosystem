# Joining a Realm

> ⚠ **Rewritten 2026-09-05.** The previous version of this guide described
> a `hecate pair` CLI, a 6-digit confirmation code, and credential storage
> under `~/.hecate/hecate-daemon/` — none of it real. `hecate-daemon` is
> obsolete (archived, deleted from local disk), and no `/api/v1/pairing/*`
> endpoints exist or ever did under that exact shape. What's below is the
> actual flow, verified live against production `realm.macula.io`: a real
> join producing a genuine `201`.

A realm is your organization's namespace on the Macula mesh: identity,
membership, and per-realm administration. Joining binds a public key —
your own, or an agent's acting on your behalf — to a person's account in
that realm, so the resulting identity can be authorized to do things on
the mesh under that person's membership.

This is `macula-realm`'s own concern, not `macula-portal`'s — the two
split into separate services on 2026-08-30 (`macula-realm` handles
membership/join; `macula-portal` handles org/app management and
licensing). Older material may point at the bare `macula.io` domain or
at `macula-portal` for this flow; both are stale.

## What is realm membership?

Realm membership is the root of trust for a human on the mesh, the same
way a service's realm-signed certificate is the root of trust for a
service. Once joined, a person's membership record can delegate
narrower, shorter-lived UCAN capability tokens to whatever's acting on
their behalf — a terminal session, a coding agent, a browser tab, a
phone.

Joining establishes:

- **Org identity** — an `mri:org:io.macula/<handle>` bound to your key
- **A refresh token** — for the realm's own API (cert renewal, session
  management)
- **A realm-CA-signed certificate** — for the key that joined

Until you join, a key can still participate in the mesh as an anonymous
peer (citizenship in the mesh-wide directory is a separate, unvouched
thing — see the mesh-membership docs), but nothing vouches for it as
belonging to a specific person or organization.

## If you're using `macula-mcp`

You don't need anything below this section. The tool is
`mesh_join_realm`: call it, hand the person the approval link/QR it
returns, then call it again with `wait_seconds` once they've had a
chance to confirm. Configuration is `MACULA_MCP_REALM_URL` (default
`https://realm.macula.io`) — see
[hecate-corpus's FAQ_MACULA_MCP.md](https://github.com/hecate-social/hecate-corpus/blob/main/guides/FAQ_MACULA_MCP.md)
for the full tool reference and
[FAQ_JOIN_A_REALM.md](https://github.com/hecate-social/hecate-corpus/blob/main/guides/FAQ_JOIN_A_REALM.md)
for the wire-level detail.

The rest of this page is that same detail, for anyone building a
different client against the same endpoint directly.

## The join-session flow

A device-authorization pattern (RFC 8628 shape, the same one used for
signing in to a TV app or CLI tool): the client requests a session,
gets back a link (and optionally a QR code of it), and the person
confirms it in their own browser while the client polls in the
background.

```
POST /api/v1/join/sessions
Content-Type: application/json

{
  "node_id":         "base64-or-hex-encoded-ed25519-public-key",
  "timestamp":        1757000000000,
  "proof_signature":  "base64-encoded-signature"
}
```

`proof_signature` proves the requester actually holds the private key
for `node_id`, not just a claimed public one: it's a signature over the
exact byte layout `node_id (32 raw bytes) ++ timestamp (8 bytes,
big-endian) ++ "macula_realm.join_session" (raw UTF-8, no delimiters)`.
The procedure string is part of the signed message, not a label — it
has to match `macula-realm`'s own `join_session_controller.ex`/
`joining.ex` `@join_procedure` exactly, or a valid signature verifies
against the wrong bytes and is rejected.

→ `201`, a ten-minute session, with an approval URL. The person opens
it, signs in (Hanko), sees which key/client is asking, and confirms.

```
GET /api/v1/join/sessions/:id
```

polls for the outcome. Once confirmed, it returns:

```json
{
  "org_identity":   "mri:org:io.macula/<handle>",
  "refresh_token":  "…",
  "cert_pem":       "-----BEGIN CERTIFICATE-----…"
}
```

The client's own private key never leaves it or crosses the wire at any
point — only the public key and a signature over it do.

## Troubleshooting

**Session expired.** Ten-minute TTL. Start a new session; the old one
is discarded on the server side, nothing to clean up manually.

**Network errors.** Confirm the target is actually `realm.macula.io`,
not `macula.io` or `macula-portal`'s domain — a request to either of
the wrong hosts fails or 404s, not because the realm is unreachable but
because you're asking the wrong service.

**Signature rejected on an otherwise-correct request.** Almost always
the procedure string baked into the signed bytes: it must be the exact
literal `macula_realm.join_session`, byte-for-byte, with no trailing
whitespace or encoding difference from what the request actually POSTs
as `timestamp`.

## Security design

- **No private key over the wire** — only the public key and a proof
  signature ever leave the client.
- **Short-lived sessions** — a ten-minute TTL bounds a stale, unconfirmed
  session's exposure.
- **Proof of possession, not just a claimed key** — the signed
  `{node_id, timestamp, procedure}` message means nobody can create a
  session for a key they don't hold and talk a person into confirming
  it.
- **Human-in-the-loop** — joining requires an authenticated person to
  actively confirm, every time.
- **Certificate-based identity after joining** — subsequent
  authentication uses the realm-CA-signed certificate, not a password
  or a long-lived static API key.
