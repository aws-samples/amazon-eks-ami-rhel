#!/bin/bash
# File: user-data-init.sh
# Ensures SSH and SSM agent are ready before Packer connects

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging function
# ---------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    logger -t user-data "$*"
}

# ---------------------------------------------------------------------------
# Helper to capture a clean single-line status string, stripping all
# whitespace/carriage-returns regardless of which branch of || ran.
# ---------------------------------------------------------------------------
get_status() {
    local raw
    raw=$(systemctl is-active "$1" 2>/dev/null || echo "unknown")
    echo "$raw" | tr -d '[:space:]'
}

log "=== User Data Initialization Started ==="

# ---------------------------------------------------------------------------
# IMDSv2 token
# ---------------------------------------------------------------------------
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        -s --max-time 5 || echo "")
if [ -z "$TOKEN" ]; then
    log "WARNING: Failed to get IMDSv2 token — continuing without metadata"
fi

# ---------------------------------------------------------------------------
# Region detection
# ---------------------------------------------------------------------------
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    -s --max-time 5 \
    http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null \
    || echo "us-gov-west-1")
REGION=$(echo "$REGION" | tr -d '[:space:]')
log "Detected region: $REGION"

# ---------------------------------------------------------------------------
# Ensure REGION DNF variable is set — required for RHUI repo resolution.
# This is normally created by rh-amazon-rhui-client on first boot but can
# be missing if cloud-init initialization order causes a race condition.
# ---------------------------------------------------------------------------
# if [ ! -f /etc/dnf/vars/REGION ]; then
#     log "WARNING: /etc/dnf/vars/REGION missing — creating from IMDSv2 region detection..."
#     mkdir -p /etc/dnf/vars
#     echo "$REGION" | tee /etc/dnf/vars/REGION >/dev/null
#     log "✓ Set /etc/dnf/vars/REGION to $REGION"
# else
#     log "✓ /etc/dnf/vars/REGION already set to: $(cat /etc/dnf/vars/REGION)"
# fi

# ---------------------------------------------------------------------------
# Trellix / McAfee — stop, disable, and mask
# ---------------------------------------------------------------------------
log "Temporarily disabling Trellix/McAfee..."
sudo systemctl stop    mfeespd mfetpd || true
sudo systemctl disable mfeespd mfetpd || true
sudo systemctl mask    mfeespd mfetpd || true
log "✓ Trellix/McAfee stopped, disabled, and masked"

# ---------------------------------------------------------------------------
# Misc terminal / shell settings
# ---------------------------------------------------------------------------
log "Disabling enable-bracketed-paste ..."
echo "set enable-bracketed-paste off" >> /etc/inputrc

# ---------------------------------------------------------------------------
# SELinux — disable early so subsequent steps are not blocked
# ---------------------------------------------------------------------------
log "Disabling SELinux..."
setenforce 0 || log "Warning: Could not set SELinux to permissive (may already be disabled)"
grubby --update-kernel ALL --args selinux=0
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
log "✓ SELinux disabled"

# ---------------------------------------------------------------------------
# Packer working directories
# ---------------------------------------------------------------------------
log "Creating Packer working directories..."
mkdir -p /opt/packer/worker
chmod -R 755 /opt/packer
chown -R ec2-user:ec2-user /opt/packer
restorecon -R /opt/packer 2>/dev/null || true
log "✓ Created /opt/packer directory"

# ---------------------------------------------------------------------------
# Restore ec2-user SSH authorized_keys from IMDSv2 if the file is missing
# ---------------------------------------------------------------------------
AUTH_KEYS="/home/ec2-user/.ssh/authorized_keys"
if [ ! -f "$AUTH_KEYS" ]; then
    PUBLIC_KEY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
        -s --max-time 5 \
        http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key \
        || echo "")
    if [ -n "$PUBLIC_KEY" ]; then
        mkdir -p /home/ec2-user/.ssh
        echo "$PUBLIC_KEY" > "$AUTH_KEYS"
        chmod 700 /home/ec2-user/.ssh
        chmod 600 "$AUTH_KEYS"
        chown -R ec2-user:ec2-user /home/ec2-user/.ssh
        restorecon -R /home/ec2-user/.ssh 2>/dev/null || true
        log "Restored authorized_keys from IMDS"
    else
        log "No public key found in IMDS"
    fi
fi

# ---------------------------------------------------------------------------
# OS version info
# ---------------------------------------------------------------------------
RHEL_VERSION=$(rpm -E %{rhel})
log "Detected RHEL version: $RHEL_VERSION"
cat /etc/os-release

# ---------------------------------------------------------------------------
# AWS CLI — Add to /etc/profile.d/ so it's available for all users including root
# ---------------------------------------------------------------------------
cat > /etc/profile.d/aws-cli.sh << 'EOF'
# AWS CLI PATH configuration
export PATH="/usr/local/aws-cli/v2/current/bin:$PATH"
EOF
chmod +x /etc/profile.d/aws-cli.sh

# ---------------------------------------------------------------------------
# SSM agent — install / start only if not already active
# ---------------------------------------------------------------------------

# FIX: capture status into a variable first, then strip whitespace separately
# so that tr -d applies to the full output and not just the echo fallback.
SSM_STATUS=$(get_status amazon-ssm-agent)
log "SSM agent status: $SSM_STATUS"

if rpm -q amazon-ssm-agent >/dev/null 2>&1 && [ "$SSM_STATUS" = "active" ]; then
    SSM_VERSION=$(rpm -q amazon-ssm-agent --qf '%{VERSION}' 2>/dev/null || echo "unknown")
    SSM_VERSION=$(echo "$SSM_VERSION" | tr -d '[:space:]')
    log "✓ SSM agent already installed and running (version: $SSM_VERSION) — skipping setup"
else
    log "SSM agent not installed or not running (status: $SSM_STATUS) — proceeding with setup..."

    # Determine the correct download URL for this region
    case "$REGION" in
        us-gov-west-1)
            SSM_URL="https://s3.us-gov-west-1.amazonaws.com/amazon-ssm-us-gov-west-1/latest/linux_amd64/amazon-ssm-agent.rpm"
            log "Using GovCloud West SSM agent URL"
            ;;
        us-gov-east-1)
            SSM_URL="https://s3.us-gov-east-1.amazonaws.com/amazon-ssm-us-gov-east-1/latest/linux_amd64/amazon-ssm-agent.rpm"
            log "Using GovCloud East SSM agent URL"
            ;;
        *)
            SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
            log "Using Commercial SSM agent URL"
            ;;
    esac

    # Download SSM agent
    cd /tmp
    if curl -f -s --max-time 60 -o amazon-ssm-agent.rpm "$SSM_URL"; then
        log "✓ Downloaded SSM agent"
        ls -al ./amazon-ssm-agent.rpm

        # Install or update
        if rpm -q amazon-ssm-agent >/dev/null 2>&1; then
            log "Updating existing SSM agent..."
            dnf update -y --disablerepo='*' ./amazon-ssm-agent.rpm 2>&1 | tee /tmp/dnf-ssm-update.log || log "Update had warnings (continuing)"
        else
            log "Installing SSM agent..."
            dnf install -y --disablerepo='*' ./amazon-ssm-agent.rpm 2>&1 | tee /tmp/dnf-ssm-install.log || log "Install had warnings (continuing)"
        fi

        rm -f amazon-ssm-agent.rpm
        log "✓ SSM agent package installed"
    else
        log "✗ WARNING: Failed to download SSM agent from $SSM_URL"
        log "Continuing without SSM agent..."
    fi

    # Enable and start SSM agent only if the binary landed on disk
    if [ -f /usr/bin/amazon-ssm-agent ]; then
        log "Starting SSM agent..."
        systemctl enable  amazon-ssm-agent 2>/dev/null || log "Could not enable SSM agent"
        systemctl start amazon-ssm-agent 2>/dev/null || log "Could not start SSM agent"

        # Give SSM a moment to initialise
        sleep 3

        # Re-check status after start attempt
        SSM_STATUS=$(get_status amazon-ssm-agent)
        if [ "$SSM_STATUS" = "active" ]; then
            SSM_VERSION=$(rpm -q amazon-ssm-agent --qf '%{VERSION}' 2>/dev/null || echo "unknown")
            SSM_VERSION=$(echo "$SSM_VERSION" | tr -d '[:space:]')
            log "✓ SSM agent is running (version: $SSM_VERSION)"
        else
            log "✗ WARNING: SSM agent installed but failed to start (status: $SSM_STATUS)"
        fi
    else
        log "✗ WARNING: SSM agent binary not found after install attempt"
    fi
fi

# ---------------------------------------------------------------------------
# Final status check
# ---------------------------------------------------------------------------
log "=== Final Status Check ==="
SSH_STATUS=$(get_status sshd)
SSM_STATUS=$(get_status amazon-ssm-agent)
log "SSH: $SSH_STATUS"
log "SSM: $SSM_STATUS"

log "SSH and SSM ready - Packer can connect now"

# Signal completion
touch /tmp/user-data-complete
log "=== User Data Initialization Complete ==="