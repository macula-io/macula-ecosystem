# Joining Your Node to a Realm

After installing Hecate, your node is running but isolated. **Pairing** connects it to your Realm — your organization's identity and trust boundary on the Macula mesh.

This guide walks you through the pairing process and explains what happens under the hood.

## What is Realm Pairing?

A Realm is your organization's namespace in Macula. It holds your identity, your apps, your certificates, and your trust relationships. Every Hecate node must be paired to a Realm before it can participate in the mesh.

Pairing establishes:

- **Identity** — your node gets a signed certificate from your Realm
- **Trust** — the Realm knows this node belongs to you
- **Connectivity** — the node can now discover and communicate with peers in your Realm

Without pairing, your node cannot publish to topics, call RPC procedures, or be discovered by other nodes.

## Prerequisites

Before pairing, you need:

1. **Hecate daemon running** — installed via HecateOS or the install script
2. **A Realm account** — sign up at [macula.io](https://macula.io) using GitHub
3. **Network access** — your node must be able to reach `macula.io` over HTTPS

Verify the daemon is running:

```bash
hecate status
```

You should see the daemon status with its node ID and public key.

## The Pairing Flow

![Node-Realm Pairing Flow](assets/node-realm-pairing.svg)

The diagram above shows the complete flow. Three actors participate:

| Actor | Role |
|-------|------|
| **You** (the user) | Initiates pairing, confirms the code |
| **Hecate Node** | Generates keypair, sends pairing request, receives credentials |
| **Macula Realm** | Validates identity, issues certificate and token |

The flow uses a **device authorization** pattern (similar to logging in to a TV app): the node requests a session, displays a short code, and you confirm that code in your browser.

## Step-by-Step

### 1. Sign in to your Realm

Go to [macula.io/sign-in](https://macula.io/sign-in) and sign in with your GitHub account. If you do not have a Realm yet, one will be created for you.

### 2. Run `hecate pair` on your node

Open a terminal on the machine running Hecate and run:

```bash
hecate pair
```

The CLI will:
- Generate an Ed25519 keypair (if one does not already exist)
- Send a pairing session request to the Realm, including the node's public key and agent info
- Display a **6-digit confirmation code**

You will see output like:

```
Pairing session started.
Enter this code at macula.io/pair/abc123:

  847 293

Waiting for confirmation... (expires in 10 minutes)
```

### 3. Enter the code in your browser

The CLI output includes a URL. Open it (or go to [macula.io](https://macula.io) and navigate to the pairing page). Enter the 6-digit code displayed on your node.

The Realm verifies the code matches the session, then:
- Creates an **application identity** for your node
- Issues a **Realm certificate** (X.509, signed by your Realm CA)
- Generates a **refresh token** for ongoing API access

### 4. Node receives credentials

The CLI is polling in the background. Once you confirm the code, the node automatically receives its credentials:

```
Pairing successful!

  Node:  hecate-abc123
  Realm: io.macula.yourname
  Cert:  valid until 2027-02-26

Your node is now part of the mesh.
```

The certificate and token are stored locally in `~/.hecate/hecate-daemon/` and used automatically for all mesh operations.

## Under the Hood

### Session API

The pairing flow uses three REST endpoints on the Realm:

| Endpoint | Purpose |
|----------|---------|
| `POST /api/v1/pairing/sessions` | Node creates a pairing session (sends public key) |
| `GET /api/v1/pairing/sessions/:id` | Node polls for session status |
| `POST /api/v1/pairing/sessions/:id/confirm` | User confirms with 6-digit code |

### Cryptography

- **Ed25519** keypair generated on the node (never leaves the device)
- **Public key** sent to Realm during session creation
- **Realm CA** signs an X.509 certificate binding the public key to the node identity
- **Refresh token** issued for API access (cert renewal, app sync)

### What gets stored

On the node (`~/.hecate/hecate-daemon/`):
- `ed25519_private.pem` — node private key (never transmitted)
- `realm_cert.pem` — signed certificate from Realm
- `refresh_token` — encrypted token for Realm API

On the Realm (database):
- Application record (node name, public key fingerprint)
- Certificate metadata (serial, expiry, revocation status)

## Troubleshooting

### Code expired

The 6-digit code is valid for **10 minutes**. If it expires, run `hecate pair` again to start a new session. Old sessions are automatically cleaned up.

### Already paired

If your node is already paired to a Realm, `hecate pair` will tell you:

```
This node is already paired to io.macula.yourname.
Use 'hecate unpair' to remove the existing pairing first.
```

### Network errors

If the node cannot reach `macula.io`:

1. Check your internet connection
2. Verify DNS resolution: `dig macula.io`
3. Check if a firewall is blocking HTTPS (port 443)
4. Try `curl -I https://macula.io/api/v1/auth/health` — you should get a `200 OK`

### Wrong Realm

If you paired to the wrong Realm, unpair and re-pair:

```bash
hecate unpair
hecate pair
```

Make sure you are signed in to the correct Realm account in your browser before confirming the code.

## Security Design

The pairing flow is designed with these security properties:

- **No secrets over the wire** — the private key never leaves the node
- **Short-lived sessions** — 10-minute TTL prevents stale session attacks
- **Single-use codes** — each code can only be confirmed once
- **User-in-the-loop** — pairing requires active confirmation from an authenticated user
- **Certificate-based identity** — after pairing, authentication uses X.509 certificates (not passwords or API keys)
- **Automatic renewal** — certificates are renewed before expiry using the refresh token

This is similar to how you pair a new device to your Apple or Google account: the device shows a code, you confirm it on a trusted device, and the new device gets credentials.
