#!/usr/bin/env bash
# Prepares a brand-new Ubuntu or Debian server for the stack: Docker, swap, log limits, a firewall, automatic
# security updates and SSH hardening. Safe to run more than once.
#
# On Hetzner Cloud paste this whole file into "Cloud config / user data" when creating the server, or copy it over and run
#   sudo bash bootstrap.sh
#
# Optional settings (environment variables):
#   STACK_REPO=git@github.com:you/stack.git   clone the stack into /opt/stack
#   SWAP_GB=2                                 size of the swap file (0 to skip)
#   SSH_HARDEN=auto|yes|no                    turn off password sign-in (auto: only if root already has an SSH key)
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run this as root (sudo bash bootstrap.sh)." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
SWAP_GB="${SWAP_GB:-2}"
SSH_HARDEN="${SSH_HARDEN:-auto}"

echo "== Packages"
apt-get update -y
apt-get install -y ca-certificates curl git ufw unattended-upgrades

echo "== Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
mkdir -p /etc/docker
# Cap container logs so they cannot fill a small disk.
cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
JSON
systemctl restart docker

echo "== Swap"
if [ "$SWAP_GB" != "0" ] && ! swapon --show | grep -q .; then
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swap.conf
  sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null
fi

echo "== Firewall"
# Note: Docker adds its own rules for published ports. The stack only publishes 80 and 443 (and loopback ports), and
# the Hetzner Cloud Firewall in front should allow only 22, 80 and 443 as well.
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "== Automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
# Updates install by themselves, but the server never reboots by itself: do that yourself when it suits you.

echo "== SSH"
has_key=no
[ -s /root/.ssh/authorized_keys ] && has_key=yes
if [ "$SSH_HARDEN" = yes ] || { [ "$SSH_HARDEN" = auto ] && [ "$has_key" = yes ]; }; then
  cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  echo "Password sign-in is now off. Keys only."
else
  echo "Skipped: root has no SSH key yet, and turning passwords off would lock you out."
fi

if [ -n "${STACK_REPO:-}" ] && [ ! -d /opt/stack/.git ]; then
  echo "== Cloning the stack"
  git clone "$STACK_REPO" /opt/stack
fi

cat <<'DONE'

Server is ready. Next:
  1. cd /opt/stack   (copy or clone the stack there if you have not)
  2. cp .env.example .env   and fill it in
  3. echo <token> | docker login ghcr.io -u <github-user> --password-stdin   (only if the images are private)
  4. ./scripts/update.sh
DONE
