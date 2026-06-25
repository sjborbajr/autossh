#!/bin/bash
set -e

KEY_DIR="/keys"
KEY_FILE="${KEY_DIR}/id_ed25519"
PUB_FILE="${KEY_DIR}/id_ed25519.pub"

# ── Validate required env vars ────────────────────────────────────────────────
if [[ -z "${SSH_USER}" || -z "${SSH_HOST}" ]]; then
  echo "ERROR: SSH_USER and SSH_HOST must be set." >&2
  exit 1
fi

SSH_PORT="${SSH_PORT:-22}"

# ── Autossh key generation ────────────────────────────────────────────────────
if [[ ! -f "${KEY_FILE}" ]]; then
  echo "No key found at ${KEY_FILE} — generating ed25519 keypair..."
  ssh-keygen -t ed25519 -N "" -f "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
  chmod 644 "${PUB_FILE}"
  echo "────────────────────────────────────────"
  echo "New public key (add this to remote authorized_keys):"
  cat "${PUB_FILE}"
  echo "────────────────────────────────────────"
else
  echo "Using existing key: ${KEY_FILE}"
fi

# ── Optional sshd setup ───────────────────────────────────────────────────────
if [[ -n "${SSH_ADMIN_USER}" && -n "${SSH_ADMIN_PUBKEY}" ]]; then
  echo "SSH_ADMIN_USER and SSH_ADMIN_PUBKEY set — configuring sshd..."
  for type in rsa ecdsa ed25519; do
    host_key="${KEY_DIR}/ssh_host_${type}_key"
    if [[ ! -f "${host_key}" ]]; then
      ssh-keygen -t "${type}" -N "" -f "${host_key}"
    fi
    chmod 600 "${host_key}"
    chmod 644 "${host_key}.pub"
    ln -sf "${host_key}" "/etc/ssh/ssh_host_${type}_key"
    ln -sf "${host_key}.pub" "/etc/ssh/ssh_host_${type}_key.pub"
  done

  # Create user if missing
  if ! id "${SSH_ADMIN_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${SSH_ADMIN_USER}"
  fi

  echo "${SSH_ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${SSH_ADMIN_USER}"
  chmod 440 "/etc/sudoers.d/${SSH_ADMIN_USER}"

  # Authorized key
  USER_HOME=$(getent passwd "${SSH_ADMIN_USER}" | cut -d: -f6)
  mkdir -p "${USER_HOME}/.ssh"
  echo "${SSH_ADMIN_PUBKEY}" > "${USER_HOME}/.ssh/authorized_keys"
  chmod 700 "${USER_HOME}/.ssh"
  chmod 600 "${USER_HOME}/.ssh/authorized_keys"
  chown -R "${SSH_ADMIN_USER}:${SSH_ADMIN_USER}" "${USER_HOME}/.ssh"

  mkdir -p /run/sshd
  echo "Starting sshd..."
  /usr/sbin/sshd
fi

# ── Build tunnel args ─────────────────────────────────────────────────────────
TUNNEL_ARGS=()
if [[ -n "${TUNNELS}" ]]; then
  IFS='|' read -ra TUNNEL_LIST <<< "${TUNNELS}"
  for tunnel in "${TUNNEL_LIST[@]}"; do
    direction="${tunnel%%:*}"
    spec="${tunnel#*:}"
    case "${direction}" in
      R|L) TUNNEL_ARGS+=("-${direction}" "${spec}") ;;
      *) echo "ERROR: Tunnel '${tunnel}' missing R: or L: prefix." >&2; exit 1 ;;
    esac
  done
fi

# ── Build verbosity flag ──────────────────────────────────────────────────────
# SSH_VERBOSE accepts SSH-style flags: v, vv, vvv (default: v). Set to 0 to silence.
if [[ "${SSH_VERBOSE}" == "0" ]]; then
  VERBOSE_FLAG=""
else
  VERBOSE_FLAG="-${SSH_VERBOSE:-v}"
fi

export AUTOSSH_GATETIME="${AUTOSSH_GATETIME:-0}"
# Set this only if you need the log persisted to a file (e.g. /keys/autossh.log), otherwise docker logs captures stderr.
if [[ -n "${AUTOSSH_LOGFILE}" ]]; then
  export AUTOSSH_LOGFILE
fi

# ── Launch autossh ────────────────────────────────────────────────────────────
exec autossh \
  -N -M 0 \
  ${VERBOSE_FLAG:+"${VERBOSE_FLAG}"} \
  -p "${SSH_PORT}" \
  -o "ExitOnForwardFailure=yes" \
  -o "ServerAliveInterval=180" \
  -o "ServerAliveCountMax=3" \
  -o "PubkeyAuthentication=yes" \
  -o "PasswordAuthentication=no" \
  -o "StrictHostKeyChecking=accept-new" \
  -o "UserKnownHostsFile=/keys/known_hosts" \
  -i "${KEY_FILE}" \
  "${TUNNEL_ARGS[@]}" \
  "${SSH_USER}@${SSH_HOST}"