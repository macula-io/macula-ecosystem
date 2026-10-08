# Joining a Realm

A realm says who belongs on the Macula mesh: which people, agents, services and devices are members. Joining binds a
key, your own or an agent's acting for you, to a person's membership in that realm, so what that key does on the mesh
can be authorized under that membership.

The realm at `https://realm.macula.io` runs on Macula's development fleet. It is not a production service.

## What joining gives you

Once a person confirms the request, the realm returns:

- **An org identity**: `mri:org:io.macula/<handle>`, bound to the key that joined.
- **A citizen id** for that key.
- **A realm-signed certificate** for the key.
- **A membership UCAN**: a post-quantum-signed capability token rooted at the person's membership, which can delegate
  narrower, shorter-lived tokens to whatever acts for them (a terminal, a coding agent, a browser tab).

The membership lasts 4 hours unless the request asks for longer, up to 30 days. Until a key joins, it can still reach
the mesh, but nothing vouches for it as belonging to a person.

## If you use `macula-mcp` or `macula-cli`

You don't need the rest of this page. In `macula-mcp` the tool is `mesh_join_realm`: call it, give the person the link
it returns, then call it again with `wait_seconds` once they have confirmed. The realm URL is `MACULA_MCP_REALM_URL`
(default `https://realm.macula.io`). See mcl-corpus's
[FAQ_MACULA_MCP.md](https://github.com/macula-services/mcl-corpus/blob/main/guides/FAQ_MACULA_MCP.md) and
[FAQ_JOIN_A_REALM.md](https://github.com/macula-services/mcl-corpus/blob/main/guides/FAQ_JOIN_A_REALM.md).

The rest is for anyone writing a client against the realm directly.

## The join-session flow

It follows the device-authorization pattern (the shape of RFC 8628, as in signing in to a TV app): the client asks for
a session, gets back a link, and the person confirms it in their own browser while the client polls.

### 1. Ask for a session

```
POST /api/v1/join/sessions
Content-Type: application/json

{
  "public_key": "<base64 of the device's carried ML-DSA-87 identity key>",
  "device_info": {"hostname": "laptop.local", "os": "unix/linux"},
  "membership_ttl_seconds": 2592000,
  "proof": {
    "v": 2,
    "timestamp": 1788352709318,
    "nonce": "<32 hex characters: 16 random bytes>",
    "signature": "<hex ML-DSA-87 signature over the proof message>"
  }
}
```

- `public_key` is the key the device carries in Macula's identity format (ML-DSA-87, or the hybrid profile's key), as
  the `macula` SDK produces it. A key of the wrong size or encoding is refused.
- `device_info` is shown to the person who confirms. It is signed, so what they read is what the device sent.
- `membership_ttl_seconds` is optional: how long the membership should last, capped at 30 days. Without it, 4 hours.
- `proof` is required.

Booleans anywhere in the body, and numbers above 2^53 - 1, are refused with `400`.

### 2. The proof

The signature is over deterministic CBOR of a map with these text keys:

| Key | Value |
|---|---|
| `tag` | the text `macula.realm.device_request` |
| `v` | `2` |
| `public_key` | the carried key, as bytes |
| `realm` | the realm id, 32 bytes |
| `procedure` | the text `macula_realm.join_session` |
| `timestamp` | the proof's `timestamp`, milliseconds |
| `nonce` | the proof's nonce, 16 bytes |
| `request` | every field of the body except `proof` (and never a `caller` field) |

The `request` map follows one rule for JSON: a string is text, an integral number is an integer (so `1` and `1.0` are
the same), any other number is a float, an object is a map with text keys, an array is a list, and `null` is null.

The realm accepts a proof within 60 seconds of its timestamp, and each nonce only once. The answers to a bad proof are:

| Status | `error` | Meaning |
|---|---|---|
| 400 | `missing_proof`, `unsupported_version`, `not_a_device_key` | the proof is absent, not version 2, or the key is not a device key |
| 401 | `stale_proof` | the timestamp is more than 60 s from the realm's clock |
| 401 | `bad_proof` | the signature does not verify over those bytes |
| 401 | `replayed` | this nonce was already used |

macula-go's [`devicerequest`](https://github.com/macula-io/macula-go/tree/master/devicerequest) package builds and
signs this message (and the TypeScript SDK uses it). Check your own implementation byte for byte against its
[test vector](https://github.com/macula-io/macula-go/blob/master/devicerequest/testdata/device_request_proof_vector.hex).

### 3. The person confirms

```json
{"session_id": "<uuid>", "join_url": "https://realm.macula.io/join/<uuid>", "expires_at": "..."}
```

The person opens `join_url`, signs in, sees which key and device are asking, and confirms. A session that is not
confirmed in time expires.

### 4. Poll for the outcome

```
GET /api/v1/join/sessions/:id
```

While waiting: `200` with `{"status": "pending", "expires_at": "..."}`. Once confirmed:

```json
{
  "status": "confirmed",
  "org_identity": "mri:org:io.macula/<handle>",
  "citizen_did": "<hex>",
  "cert_pem": "-----BEGIN CERTIFICATE-----...",
  "ucan": "<the membership UCAN>"
}
```

An expired session answers `410` with `session_expired`: start a new one. An unknown id answers `404`.

## Security design

- **No private key on the wire.** Only the public key and a signature leave the device.
- **Proof of possession, for this request, once.** The signature covers the key, this realm, the procedure, the time,
  a nonce and every field of the request, so nobody can open a session for a key they don't hold, change what the
  person reads, or replay a captured request after 60 seconds. The realm forgets used nonces when it restarts, so a
  captured proof could be accepted once more within its 60-second window.
- **Post-quantum signatures.** Keys and proofs use ML-DSA-87.
- **A person in the loop.** Joining needs a signed-in person to confirm, every time.
- **Short sessions, bounded memberships.** An unconfirmed session expires, and a membership lasts at most 30 days.
