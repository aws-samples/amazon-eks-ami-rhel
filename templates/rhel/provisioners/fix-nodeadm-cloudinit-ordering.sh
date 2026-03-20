#!/usr/bin/env bash
# File: fix-nodeadm-cloudinit-ordering.sh
#
# Fixes three issues that prevent EKS nodes from joining the cluster on RHEL9
# when cloud-init version 24.4+ is present.
#
# Issue 1 — systemd ordering cycle via WantedBy=multi-user.target:
#   cloud-init 24.4 changed systemd ordering so that cloud-final runs
#   AFTER multi-user.target. Both nodeadm-run.service and
#   nodeadm-boot-hook.service declare:
#     After=cloud-final.service
#     WantedBy=multi-user.target
#   This creates a cycle:
#     multi-user.target → nodeadm-* → cloud-final → multi-user.target
#   systemd breaks the cycle by deleting the nodeadm start jobs,
#   meaning kubelet never starts and the node never joins the EKS cluster.
#
#   Fix: Change WantedBy=multi-user.target to WantedBy=cloud-init.target
#   so nodeadm services are ordered under cloud-init.target instead.
#
# Issue 2 — residual ordering cycle via After=cloud-final.service:
#   Even after fixing WantedBy, the After=cloud-final.service directive
#   creates a second cycle:
#     cloud-init.target → nodeadm-run → After=cloud-final
#     cloud-final → must complete before cloud-init.target
#   systemd still detects this as a cycle and deletes the nodeadm-run
#   start job. The After=cloud-final.service must be removed entirely.
#   nodeadm-run only needs to run after nodeadm-config.service, which
#   is the legitimate sequential dependency and is safe to keep.
#
#   Fix: Remove cloud-final.service from the After= directive, leaving
#   only After=nodeadm-config.service.
#
# Issue 3 — missing /usr/bin/networkctl (systemd-networkd not installed):
#   nodeadm-internal writes systemd-networkd config files to
#   /run/systemd/network/ and then calls "networkctl reload" via the
#   udev-net-manager@eth0.service ExecStartPost directive.
#   On RHEL9 with NetworkManager, systemd-networkd is not installed by
#   default, so networkctl is missing and the service fails and retries
#   continuously until it hits the restart limit.
#
#   Fix: Create a /usr/bin/networkctl shim that translates the reload
#   call to the NetworkManager equivalent (nmcli general reload).
#
# Issue 4 — nm-cloud-setup re-enabled by NetworkManager-cloud-setup RPM:
#   The NetworkManager-cloud-setup package post-install scriptlet
#   re-enables nm-cloud-setup.timer and nm-cloud-setup.service whenever
#   the package is installed or upgraded. This causes network routing
#   disruption on EKS nodes. Masking (symlink to /dev/null) prevents
#   any package operation from re-enabling them.
#
#   Fix: Mask both nm-cloud-setup units so they cannot be re-enabled
#   by any subsequent package install or upgrade.
#
# References:
#   https://github.com/aws-samples/amazon-eks-ami-rhel/pull/20
#   https://cloudinit.readthedocs.io/en/latest/reference/breaking_changes.html#id4

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== fix-nodeadm-cloudinit-ordering: start ==="

# ---------------------------------------------------------------------------
# Issues 1 & 2: Fix systemd ordering cycle in nodeadm service files
#   - Change WantedBy=multi-user.target → WantedBy=cloud-init.target
#   - Remove cloud-final.service from After= directive
# Applies to both nodeadm-run.service and nodeadm-boot-hook.service
# ---------------------------------------------------------------------------

NODEADM_SERVICES=(
    "/etc/systemd/system/nodeadm-run.service"
    "/etc/systemd/system/nodeadm-boot-hook.service"
)

DAEMON_RELOAD_NEEDED=false

for SERVICE_FILE in "${NODEADM_SERVICES[@]}"; do
    if [ ! -f "$SERVICE_FILE" ]; then
        log "  ⚠ $SERVICE_FILE not found — skipping"
        continue
    fi

    log "  Processing $SERVICE_FILE..."

    # Fix 1: WantedBy=multi-user.target → WantedBy=cloud-init.target
    if grep -q "WantedBy=multi-user.target" "$SERVICE_FILE"; then
        log "  Found WantedBy=multi-user.target — applying fix..."
        sudo sed -i \
            's/WantedBy=multi-user.target/WantedBy=cloud-init.target/' \
            "$SERVICE_FILE"
        if grep -q "WantedBy=cloud-init.target" "$SERVICE_FILE"; then
            log "  ✓ Fixed WantedBy in $SERVICE_FILE"
            DAEMON_RELOAD_NEEDED=true
        else
            log "  ✗ ERROR: WantedBy sed substitution did not apply to $SERVICE_FILE"
            exit 1
        fi
    else
        log "  ✓ WantedBy already correct in $SERVICE_FILE — skipping"
    fi

    # Fix 2: Remove cloud-final.service from After= directive
    # After=cloud-final.service creates a cycle when WantedBy=cloud-init.target:
    #   cloud-init.target → nodeadm-run → After=cloud-final → cloud-init.target
    # nodeadm-run only needs After=nodeadm-config.service which is safe to keep.
    if grep -q "After=.*cloud-final\.service" "$SERVICE_FILE"; then
        log "  Found cloud-final.service in After= directive — removing..."
        sudo sed -i \
            's/ cloud-final\.service//' \
            "$SERVICE_FILE"
        # Also handle case where cloud-final.service appears first in the list
        sudo sed -i \
            's/After=cloud-final\.service /After=/' \
            "$SERVICE_FILE"
        # Also handle case where cloud-final.service is the only After= value
        sudo sed -i \
            's/After=cloud-final\.service$/After=/' \
            "$SERVICE_FILE"
        if ! grep -q "cloud-final.service" "$SERVICE_FILE"; then
            log "  ✓ Removed cloud-final.service from After= in $SERVICE_FILE"
            DAEMON_RELOAD_NEEDED=true
        else
            log "  ✗ ERROR: cloud-final.service still present in $SERVICE_FILE"
            exit 1
        fi
    else
        log "  ✓ cloud-final.service not in After= in $SERVICE_FILE — skipping"
    fi

    # Show final Unit and Install sections for build log audit trail
    log "  --- [Unit] section of $SERVICE_FILE ---"
    grep -A5 "^\[Unit\]" "$SERVICE_FILE" || true
    log "  --- [Install] section of $SERVICE_FILE ---"
    grep -A2 "^\[Install\]" "$SERVICE_FILE" || true
    log "  ---"
done

if [ "$DAEMON_RELOAD_NEEDED" = true ]; then
    sudo systemctl daemon-reload
    log "✓ systemctl daemon-reload complete"
fi

# ---------------------------------------------------------------------------
# Issue 3: Create /usr/bin/networkctl shim for NetworkManager systems
# nodeadm-internal calls "networkctl reload" after writing network config.
# On RHEL9 with NetworkManager (not systemd-networkd), networkctl is absent.
# ---------------------------------------------------------------------------

NETWORKCTL="/usr/bin/networkctl"

if [ -f "$NETWORKCTL" ]; then
    log "✓ $NETWORKCTL already exists — skipping shim creation"
else
    log "Creating $NETWORKCTL shim (translates networkctl → nmcli)..."

    sudo tee "$NETWORKCTL" > /dev/null << 'EOF'
#!/usr/bin/env bash
# networkctl shim — translates systemd-networkd calls to NetworkManager
# Created by fix-nodeadm-cloudinit-ordering.sh during AMI build
# Required because nodeadm-internal calls "networkctl reload" after writing
# /run/systemd/network/ config files, but RHEL9 uses NetworkManager.
case "$1" in
    reload)
        nmcli general reload
        ;;
    *)
        # Silently ignore other networkctl subcommands
        # nodeadm only uses "reload" so this is safe
        exit 0
        ;;
esac
EOF

    sudo chmod +x "$NETWORKCTL"

    if [ -x "$NETWORKCTL" ]; then
        log "✓ $NETWORKCTL shim created and marked executable"
    else
        log "✗ ERROR: Failed to create $NETWORKCTL shim"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Issue 4: Mask nm-cloud-setup to prevent NetworkManager-cloud-setup RPM
# from re-enabling it during package installs in the bootstrap script.
# Masking (symlink → /dev/null) cannot be undone by any package operation.
# ---------------------------------------------------------------------------

log "Masking nm-cloud-setup (NetworkManager-cloud-setup RPM enables it on install)..."
sudo systemctl mask nm-cloud-setup.timer
sudo systemctl mask nm-cloud-setup.service

NM_TIMER=$(systemctl is-enabled nm-cloud-setup.timer 2>/dev/null || true)
NM_SERVICE=$(systemctl is-enabled nm-cloud-setup.service 2>/dev/null || true)
log "nm-cloud-setup.timer:   ${NM_TIMER}"
log "nm-cloud-setup.service: ${NM_SERVICE}"

if [ "$NM_TIMER" = "masked" ] && [ "$NM_SERVICE" = "masked" ]; then
    log "✓ nm-cloud-setup successfully masked"
else
    log "✗ ERROR: nm-cloud-setup masking did not apply correctly"
    exit 1
fi

# ---------------------------------------------------------------------------
# Final verification — confirm all fixes applied correctly
# ---------------------------------------------------------------------------

log "=== final verification ==="

for SERVICE_FILE in "${NODEADM_SERVICES[@]}"; do
    if [ ! -f "$SERVICE_FILE" ]; then
        continue
    fi
    WANTED_BY=$(grep "WantedBy" "$SERVICE_FILE" || echo "NOT FOUND")
    AFTER=$(grep "^After=" "$SERVICE_FILE" || echo "NOT FOUND")
    log "  $SERVICE_FILE"
    log "    After=:    $AFTER"
    log "    WantedBy:  $WANTED_BY"
    if echo "$WANTED_BY" | grep -q "cloud-init.target" && \
       ! grep -q "cloud-final.service" "$SERVICE_FILE"; then
        log "    ✓ ordering is correct — no cycle"
    else
        log "    ✗ WARNING: ordering may still cause a cycle"
    fi
done

log "=== fix-nodeadm-cloudinit-ordering: complete ==="
