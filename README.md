# autossh-tunnel

A Docker container that maintains persistent SSH tunnels (reverse and/or local) via `autossh`. Optionally runs an internal `sshd` to allow inbound admin access over the tunnel.

Designed for remote support scenarios: deploy at a customer site, establish a reverse tunnel back to your server, and connect in whenever needed.

---

## How it works

On startup the container:

1. Generates an ed25519 keypair in `/keys` if one doesn't exist, and prints the public key.
2. Optionally starts `sshd` inside the container for admin access.
3. Launches `autossh` to establish and maintain the configured tunnels.

All state (SSH keys, known hosts) is persisted in the `/keys` volume so it survives container restarts and re-creation.

---

## Quick start

docker run -d --restart on-failure \
  -e SSH_USER=user \
  -e SSH_HOST=host.contoso.org \
  -e TUNNELS="R:0.0.0.0:10022:127.0.0.1:22" \
  -v ./keys:/keys \
  autossh-tunnel

---

## Environment variables

### Required

| Variable   | Description                        |
|------------|------------------------------------|
| `SSH_USER` | Username on the remote SSH server  |
| `SSH_HOST` | Hostname or IP of the remote server |

### Optional

| Variable           | Default | Description |
|--------------------|---------|-------------|
| `SSH_PORT`         | `22`    | SSH port on the remote server |
| `TUNNELS`          | _(none)_ | Pipe-separated tunnel specs (see below) |
| `SSH_VERBOSE`      | `v`     | SSH verbosity: `v`, `vv`, `vvv`, or `0` to silence |
| `AUTOSSH_LOGFILE`  | _(stderr)_ | Persist autossh log to a file (e.g. `/keys/autossh.log`). Not needed for `docker logs` — autossh logs to stderr by default, which Docker captures. |
| `SSH_ADMIN_USER`   | _(unset)_ | If set, creates this user and starts `sshd` |
| `SSH_ADMIN_PUBKEY` | _(unset)_ | Public key to authorize for `SSH_ADMIN_USER` |

---

## Tunnel syntax

`TUNNELS` is a `|`-separated list of tunnel specs, each prefixed with `R:` or `L:`:

```
TUNNELS: "R:bind:remoteport:localhost:localport|L:bind:localport:remotehost:remoteport"
```

| Prefix | Type    | Direction |
|--------|---------|-----------|
| `R:`   | Reverse | Exposes a local port on the remote server |
| `L:`   | Local   | Pulls a remote port into the container |

### Examples

**Reverse tunnel — expose this machine's SSH to the remote server:**
```
R:0.0.0.0:10022:127.0.0.1:22
```
Connect from your server: `ssh -p 10022 user@localhost`

**Local forward — pull a remote RDP port into the container:**
```
L:0.0.0.0:3389:127.0.0.1:3389
```
To reach it from the Docker host, add a `ports:` mapping to `compose.yml`:
```yaml
ports:
  - "3389:3389"
```

**Combined (the default example):**
```
R:0.0.0.0:10022:127.0.0.1:22|L:0.0.0.0:3389:127.0.0.1:3389
```

---

## Admin SSH access (optional sshd)

Setting `SSH_ADMIN_USER` and `SSH_ADMIN_PUBKEY` starts an `sshd` inside the container, accessible via the reverse tunnel.

```yaml
SSH_ADMIN_USER: admin
SSH_ADMIN_PUBKEY: "ssh-ed25519 AAAA..."
```

- The user is created with a home directory and `/bin/bash` shell.
- The user has passwordless `sudo` — escalate with `sudo -i` or `sudo su`.
- `sshd` host keys are generated and persisted in `/keys` so clients don't get host-key-mismatch warnings on container re-creation.
- `su` to root directly requires a root password, which is not set; use `sudo` instead.

To expose the admin `sshd` to your remote server via a reverse tunnel, add to `TUNNELS`:
```
R:127.0.0.1:2222:127.0.0.1:22
```
Then from your server: `ssh -p 2222 admin@localhost`

---

## Host key trust (TOFU)

On first connection, `autossh` automatically trusts and records the remote server's host key (`StrictHostKeyChecking=accept-new`). This is Trust On First Use (TOFU): subsequent connections verify against the stored key.

The known hosts file is persisted at `/keys/known_hosts`. Without this setting, SSH would prompt interactively — which hangs a containerized, non-interactive process indefinitely.

---

## Keys volume

Mount a host directory to `/keys`. The container writes and reads:

| File | Description |
|------|-------------|
| `id_ed25519` | autossh private key (never share) |
| `id_ed25519.pub` | autossh public key (add to remote `authorized_keys`) |
| `known_hosts` | Remote server host key store |
| `ssh_host_*_key` | sshd host keys (if admin sshd is enabled) |
| `autossh.log` | autossh log (if `AUTOSSH_LOGFILE` is set) |

> **Important:** Add `keys/` to `.gitignore`. Never commit this directory.

---

## License

MIT
