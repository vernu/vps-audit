#!/usr/bin/env bash

VPS_AUDIT_VERSION="0.2.0"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# -----------------------------------------
# Configuration
# -----------------------------------------

# Static Directory/File Variables
OS_RELEASE_FILE="/etc/os-release"
REBOOT_REQUIRED_FILE="/var/run/reboot-required"
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
AUTH_LOG_FILE="/var/log/auth.log"
SUDOERS_FILE="/etc/sudoers"
PASSWORD_QUALITY_CONF="/etc/security/pwquality.conf"
FAIL2BAN_CONFIG_DIR="/etc/fail2ban"

# Resource Usage Thresholds (Disk/Memory/CPU %)
RESOURCE_WARN=50  # WARN if usage is >= 50%
RESOURCE_FAIL=80  # FAIL if usage is >= 80%

# Running Services Thresholds
SERVICES_WARN=20  # WARN if >= 20 services are running
SERVICES_FAIL=40  # FAIL if >= 40 services are running

# Failed Logins Thresholds (Count)
LOGINS_WARN=10    # WARN if >= 10 failed logins
LOGINS_FAIL=50    # FAIL if >= 50 failed logins

# Open Ports Thresholds (Count)
OPEN_PORTS_WARN=10  # WARN if >= 10 open ports
OPEN_PORTS_FAIL=20  # FAIL if >= 20 open ports

# Password Policy
PASSWORD_MINLEN=12  # PASS if pwquality minlen is >= this value

# Report Output Configuration

# Directory and File Naming
DEFAULT_REPORT_DIR="."   # Where reports will be saved
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILENAME="vps-audit-report-${TIMESTAMP}.txt"
REPORT_FILE="${DEFAULT_REPORT_DIR}/${REPORT_FILENAME}"

# Ownership
ENABLE_CHOWN=false  # Whether to chown the report (and the report dir, if created)
# Defaults to the user who invoked sudo, so reports are not left owned by root.
CHOWN_USER="${SUDO_USER:-$(id -un)}"
REPORT_CHOWN_OWNER="${CHOWN_USER}:$(id -gn "$CHOWN_USER" 2>/dev/null || id -gn)"

# Ensure report directory exists
if [ ! -d "$DEFAULT_REPORT_DIR" ]; then
    if mkdir -p "$DEFAULT_REPORT_DIR"; then
        # Apply ownership only when directory was created
        if [ "$ENABLE_CHOWN" = true ]; then
            if ! chown "$REPORT_CHOWN_OWNER" "$DEFAULT_REPORT_DIR"; then
                echo -e "${RED}[ERROR] Failed to change ownership of ${DEFAULT_REPORT_DIR}.${NC}" >&2
            fi
        fi
    else
        echo -e "${RED}[ERROR] Failed to create directory ${DEFAULT_REPORT_DIR}. Using current directory.${NC}" >&2
        DEFAULT_REPORT_DIR="."
        REPORT_FILE="./${REPORT_FILENAME}"
        ENABLE_CHOWN=false
    fi
fi

# -----------------------------------------
# End Configuration
# -----------------------------------------

print_header() {
    local header="$1"
    echo -e "\n${BLUE}${BOLD}$header${NC}"
    echo -e "\n$header" >> "$REPORT_FILE"
    echo "================================" >> "$REPORT_FILE"
}

print_info() {
    local label="$1"
    local value="$2"
    echo -e "${BOLD}$label:${NC} $value"
    echo "$label: $value" >> "$REPORT_FILE"
}

# Start the audit
echo -e "${BLUE}${BOLD}VPS Security Audit Tool v${VPS_AUDIT_VERSION}${NC}"
echo -e "${GRAY}https://nuverlabs.com/vps-audit${NC}"
echo -e "${GRAY}Starting audit at $(date)${NC}\n"

echo "VPS Security Audit Tool v${VPS_AUDIT_VERSION}" > "$REPORT_FILE"
echo "https://nuverlabs.com/vps-audit" >> "$REPORT_FILE"
echo "Starting audit at $(date)" >> "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"

# System Information Section
print_header "System Information"

# Get system information
OS_INFO=$(grep PRETTY_NAME "$OS_RELEASE_FILE" | cut -d'"' -f2)
KERNEL_VERSION=$(uname -r)
HOSTNAME=$HOSTNAME
UPTIME=$(uptime -p)
UPTIME_SINCE=$(uptime -s)
CPU_INFO=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -h | awk '/^Mem:/ {print $2}')
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}')
PUBLIC_IP=$(curl -s https://api.ipify.org)
LOAD_AVERAGE=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# Print system information
print_info "Hostname" "$HOSTNAME"
print_info "Operating System" "$OS_INFO"
print_info "Kernel Version" "$KERNEL_VERSION"
print_info "Uptime" "$UPTIME (since $UPTIME_SINCE)"
print_info "CPU Model" "$CPU_INFO"
print_info "CPU Cores" "$CPU_CORES"
print_info "Total Memory" "$TOTAL_MEM"
print_info "Total Disk Space" "$TOTAL_DISK"
print_info "Public IP" "$PUBLIC_IP"
print_info "Load Average" "$LOAD_AVERAGE"

echo "" >> "$REPORT_FILE"

# Security Audit Section
print_header "Security Audit Results"

# Function to check and report with three states
check_security() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    case $status in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[PASS] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[WARN] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[FAIL] $test_name - $message" >> "$REPORT_FILE"
            ;;
    esac
    echo "" >> "$REPORT_FILE"
}

# Check system uptime
UPTIME=$(uptime -p)
UPTIME_SINCE=$(uptime -s)
echo -e "\nSystem Uptime Information:" >> "$REPORT_FILE"
echo "Current uptime: $UPTIME" >> "$REPORT_FILE"
echo "System up since: $UPTIME_SINCE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo -e "System Uptime: $UPTIME (since $UPTIME_SINCE)"

# Check if system requires restart
if [ -f "$REBOOT_REQUIRED_FILE" ]; then
    check_security "System Restart" "WARN" "System requires a restart to apply updates"
else
    check_security "System Restart" "PASS" "No restart required"
fi

# Check SSH config overrides
SSH_CONFIG_OVERRIDES=$(grep "^Include" "$SSH_CONFIG_FILE" 2>/dev/null | awk '{print $2}')

# Check SSH root login (handle both main config and overrides if they exist)
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_ROOT=$(grep "^PermitRootLogin" $SSH_CONFIG_OVERRIDES "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_ROOT=$(grep "^PermitRootLogin" "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_ROOT" ]; then
    SSH_ROOT="prohibit-password"
fi
if [ "$SSH_ROOT" = "no" ]; then
    check_security "SSH Root Login" "PASS" "Root login is properly disabled in SSH configuration"
else
    check_security "SSH Root Login" "FAIL" "Root login is currently allowed - this is a security risk. Disable it in $SSH_CONFIG_FILE"
fi

# Check SSH password authentication (handle both main config and overrides if they exist)
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_PASSWORD=$(grep "^PasswordAuthentication" $SSH_CONFIG_OVERRIDES "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_PASSWORD=$(grep "^PasswordAuthentication" "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_PASSWORD" ]; then
    SSH_PASSWORD="yes"
fi
if [ "$SSH_PASSWORD" = "no" ]; then
    check_security "SSH Password Auth" "PASS" "Password authentication is disabled, key-based auth only"
else
    check_security "SSH Password Auth" "FAIL" "Password authentication is enabled - consider using key-based authentication only"
fi

# Check for default/unsecure SSH ports 
UNPRIVILEGED_PORT_START=$(sysctl -n net.ipv4.ip_unprivileged_port_start)
SSH_PORT=""
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_PORT=$(grep "^Port" $SSH_CONFIG_OVERRIDES "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_PORT=$(grep "^Port" "$SSH_CONFIG_FILE" 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi

if [ "$SSH_PORT" = "22" ]; then
    check_security "SSH Port" "WARN" "Using default port 22 - consider changing to a non-standard port for security by obscurity"
elif [ "$SSH_PORT" -ge "$UNPRIVILEGED_PORT_START" ]; then
    check_security "SSH Port" "FAIL" "Using unprivileged port $SSH_PORT - use a port below $UNPRIVILEGED_PORT_START for better security"
else
    check_security "SSH Port" "PASS" "Using non-default port $SSH_PORT which helps prevent automated attacks"
fi

# Check Firewall Status
check_firewall_status() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -qw "active"; then
            check_security "Firewall Status (UFW)" "PASS" "UFW firewall is active and protecting your system"
        else
            check_security "Firewall Status (UFW)" "FAIL" "UFW firewall is not active - your system is exposed to network attacks"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            check_security "Firewall Status (firewalld)" "PASS" "Firewalld is active and protecting your system"
        else
            check_security "Firewall Status (firewalld)" "FAIL" "Firewalld is not active - your system is exposed to network attacks"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -L -n | grep -q "Chain INPUT"; then
            check_security "Firewall Status (iptables)" "PASS" "iptables rules are active and protecting your system"
        else
            check_security "Firewall Status (iptables)" "FAIL" "No active iptables rules found - your system may be exposed"
        fi
    elif command -v nft >/dev/null 2>&1; then
        if nft list ruleset | grep -q "table"; then
            check_security "Firewall Status (nftables)" "PASS" "nftables rules are active and protecting your system"
        else
            check_security "Firewall Status (nftables)" "FAIL" "No active nftables rules found - your system may be exposed"
        fi
    else
        check_security "Firewall Status" "FAIL" "No recognized firewall tool is installed on this system"
    fi
}

# Firewall check
check_firewall_status

# Check for unattended upgrades
if dpkg -l | grep -q "unattended-upgrades"; then
    check_security "Unattended Upgrades" "PASS" "Automatic security updates are configured"
else
    check_security "Unattended Upgrades" "FAIL" "Automatic security updates are not configured - system may miss critical updates"
fi

# Check Intrusion Prevention Systems (Fail2ban or CrowdSec)
IPS_INSTALLED=0
IPS_ACTIVE=0

if dpkg -l | grep -q "fail2ban"; then
    IPS_INSTALLED=1
    systemctl is-active fail2ban >/dev/null 2>&1 && IPS_ACTIVE=1
fi

# Check docker container running fail2ban
if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker; then
        if docker ps -a | awk '{print $2}' | grep "fail2ban" >/dev/null 2>&1; then
            IPS_INSTALLED=1
            docker ps | grep -q "fail2ban" && IPS_ACTIVE=1
        fi
    else
        check_security "Intrusion Prevention" "WARN" "Docker is installed but not running - cannot check for Fail2ban containers"
    fi
fi

if dpkg -l | grep -q "crowdsec"; then
    IPS_INSTALLED=1
    systemctl is-active crowdsec >/dev/null 2>&1 && IPS_ACTIVE=1
fi

# Check docker container running crowdsec
if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker; then
        if docker ps -a | awk '{print $2}' | grep "crowdsec" >/dev/null 2>&1; then
            IPS_INSTALLED=1
            docker ps | grep -q "crowdsec" && IPS_ACTIVE=1
        fi
    else
        check_security "Intrusion Prevention" "WARN" "Docker is installed but not running - cannot check for CrowdSec containers"
    fi
fi

case "$IPS_INSTALLED$IPS_ACTIVE" in
    "11") check_security "Intrusion Prevention" "PASS" "Fail2ban or CrowdSec is installed and running" ;;
    "10") check_security "Intrusion Prevention" "WARN" "Fail2ban or CrowdSec is installed but not running" ;;
    *)    check_security "Intrusion Prevention" "FAIL" "No intrusion prevention system (Fail2ban or CrowdSec) is installed" ;;
esac

# Resolve a port token to a number. Accepts a numeric port or a service name
# such as "ssh", which fail2ban uses by default.
resolve_port_token() {
    local token="$1"
    if [[ "$token" =~ ^[0-9]+$ ]]; then
        echo "$token"
    else
        getent services "$token" 2>/dev/null | head -1 | awk '{print $2}' | cut -d'/' -f1
    fi
}

# Test whether a fail2ban port list ("ssh", "2022", "ssh,2222", "0:65535")
# covers a specific port number.
port_list_contains() {
    local list="$1" target="$2" token start end resolved
    local IFS=','
    for token in $list; do
        token="${token//[[:space:]]/}"
        [ -z "$token" ] && continue
        if [[ "$token" == *:* ]]; then
            start=$(resolve_port_token "${token%%:*}")
            end=$(resolve_port_token "${token##*:}")
            if [[ "$start" =~ ^[0-9]+$ ]] && [[ "$end" =~ ^[0-9]+$ ]]; then
                if [ "$target" -ge "$start" ] && [ "$target" -le "$end" ]; then
                    return 0
                fi
            fi
        else
            resolved=$(resolve_port_token "$token")
            [ "$resolved" = "$target" ] && return 0
        fi
    done
    return 1
}

# Read an option from a jail section, honouring fail2ban's file precedence:
# jail.conf, then jail.d/*.conf, then jail.local, then jail.d/*.local (last wins).
get_jail_option() {
    local section="$1" option="$2" file value result=""
    for file in "$FAIL2BAN_CONFIG_DIR/jail.conf" \
                "$FAIL2BAN_CONFIG_DIR"/jail.d/*.conf \
                "$FAIL2BAN_CONFIG_DIR/jail.local" \
                "$FAIL2BAN_CONFIG_DIR"/jail.d/*.local; do
        [ -f "$file" ] || continue
        value=$(awk -v sect="$section" -v opt="$option" '
            $0 ~ /^[[:space:]]*\[/ {
                in_sect = ($0 ~ "^[[:space:]]*\\[" sect "\\][[:space:]]*$")
                next
            }
            in_sect && $0 ~ "^[[:space:]]*" opt "[[:space:]]*=" {
                sub(/^[^=]*=[[:space:]]*/, "")
                sub(/[[:space:]]+$/, "")
                val = $0
            }
            END { if (val != "") print val }
        ' "$file" 2>/dev/null)
        [ -n "$value" ] && result="$value"
    done
    echo "$result"
}

# Check that fail2ban's SSH jail actually covers the port sshd listens on.
# The [sshd] jail inherits "port = ssh" (22) from jail.conf. When sshd runs on a
# non-standard port, the generated firewall rule still targets 22, so every ban is
# a silent no-op - while fail2ban keeps reporting the bans as successful.
check_fail2ban_port_alignment() {
    # Only meaningful when fail2ban itself is present.
    if ! command -v fail2ban-client >/dev/null 2>&1 || [ ! -d "$FAIL2BAN_CONFIG_DIR" ]; then
        return
    fi

    # Prefer sshd's own resolved config over grepping the files by hand.
    local ssh_effective_port
    ssh_effective_port=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
    [ -z "$ssh_effective_port" ] && ssh_effective_port="$SSH_PORT"
    if ! [[ "$ssh_effective_port" =~ ^[0-9]+$ ]]; then
        check_security "Fail2ban Port Alignment" "WARN" "Could not determine the effective SSH port - verify the fail2ban jail port manually"
        return
    fi

    local jail_enabled jail_port jail_banaction
    jail_enabled=$(get_jail_option "sshd" "enabled")
    jail_port=$(get_jail_option "sshd" "port")
    jail_banaction=$(get_jail_option "sshd" "banaction")
    [ -z "$jail_banaction" ] && jail_banaction=$(get_jail_option "DEFAULT" "banaction")
    [ -z "$jail_port" ] && jail_port="ssh"

    if [ "$jail_enabled" != "true" ]; then
        check_security "Fail2ban Port Alignment" "WARN" "The fail2ban [sshd] jail is not enabled - SSH brute force attempts are not being blocked"
        return
    fi

    # An allports banaction blocks every port, so the jail port is irrelevant.
    if [[ "$jail_banaction" == *allports* ]]; then
        check_security "Fail2ban Port Alignment" "PASS" "The fail2ban [sshd] jail bans all ports (banaction=$jail_banaction), so SSH on port $ssh_effective_port is covered"
        return
    fi

    if port_list_contains "$jail_port" "$ssh_effective_port"; then
        check_security "Fail2ban Port Alignment" "PASS" "The fail2ban [sshd] jail covers the active SSH port $ssh_effective_port"
    else
        check_security "Fail2ban Port Alignment" "FAIL" "The fail2ban [sshd] jail blocks port '$jail_port' but SSH listens on $ssh_effective_port - every ban is silently ineffective. Set 'port = $ssh_effective_port' in $FAIL2BAN_CONFIG_DIR/jail.local, or use banaction = nftables[type=allports]"
    fi
}

# Fail2ban jail port alignment check
check_fail2ban_port_alignment

# Check failed login attempts
if [ -f "$AUTH_LOG_FILE" ]; then
    FAILED_LOGINS=$(grep -c "Failed password" "$AUTH_LOG_FILE" 2>/dev/null || echo 0)

# if debian version > 10, info in journalctl
elif [ -f "/etc/debian_version" ]; then
    DEB_VERSION=$(cut -d'.' -f1 /etc/debian_version)
    if [ "$DEB_VERSION" -gt 10 ]; then
        FAILED_LOGINS=$(journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || echo 0)
    else
        FAILED_LOGINS=0
        check_security "Auth Log" "WARN" "Log file $AUTH_LOG_FILE not found or unreadable. Assuming 0 failed login attempts."
    fi
else
    FAILED_LOGINS=0
    check_security "Auth Log" "WARN" "Log file $AUTH_LOG_FILE not found or unreadable. Assuming 0 failed login attempts."
fi

# Ensure FAILED_LOGINS is numeric and strip whitespace
FAILED_LOGINS=$(echo "$FAILED_LOGINS" | tr -d '[:space:]')
# Remove leading zeros (if any)
FAILED_LOGINS=$((10#$FAILED_LOGINS)) # Use arithmetic evaluation to ensure it's numeric and format correctly.

if [ "$FAILED_LOGINS" -lt $LOGINS_WARN ]; then
    check_security "Failed Logins" "PASS" "Only $FAILED_LOGINS failed login attempts detected - this is within normal range"
elif [ "$FAILED_LOGINS" -lt $LOGINS_FAIL ]; then
    check_security "Failed Logins" "WARN" "$FAILED_LOGINS failed login attempts detected - might indicate breach attempts"
else
    check_security "Failed Logins" "FAIL" "$FAILED_LOGINS failed login attempts detected - possible brute force attack in progress"
fi

# Check system updates
UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | cut -d" " -f1)
if [ -z "$UPDATES" ]; then
    UPDATES=0
fi
if [ "$UPDATES" -eq 0 ]; then
    check_security "System Updates" "PASS" "All system packages are up to date"
else
    check_security "System Updates" "FAIL" "$UPDATES security updates available - system is vulnerable to known exploits"
fi

# Check running services
SERVICES=$(systemctl list-units --type=service --state=running | grep -c "loaded active running")
if [ "$SERVICES" -lt $SERVICES_WARN ]; then
    check_security "Running Services" "PASS" "Running minimal services ($SERVICES) - good for security"
elif [ "$SERVICES" -lt $SERVICES_FAIL ]; then
    check_security "Running Services" "WARN" "$SERVICES services running - consider reducing attack surface"
else
    check_security "Running Services" "FAIL" "Too many services running ($SERVICES) - increases attack surface"
fi

# Check ports using netstat or ss
if command -v netstat >/dev/null 2>&1; then
    LISTENING_PORTS=$(netstat -tuln | grep LISTEN | awk '{print $4}')
elif command -v ss >/dev/null 2>&1; then
    LISTENING_PORTS=$(ss -tuln | grep LISTEN | awk '{print $5}')
else
    check_security "Port Scanning" "FAIL" "Neither 'netstat' nor 'ss' is available on this system."
    LISTENING_PORTS=""
fi

# Process LISTENING_PORTS to extract unique public ports
if [ -n "$LISTENING_PORTS" ]; then
    PUBLIC_PORTS=$(echo "$LISTENING_PORTS" | awk -F':' '{print $NF}' | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
    PORT_COUNT=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)
    INTERNET_PORTS=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)

    if [ "$PORT_COUNT" -lt $OPEN_PORTS_WARN ] && [ "$INTERNET_PORTS" -lt 3 ]; then
        check_security "Port Security" "PASS" "Good configuration (Total: $PORT_COUNT, Public: $INTERNET_PORTS accessible ports): $PUBLIC_PORTS"
    elif [ "$PORT_COUNT" -lt $OPEN_PORTS_FAIL ] && [ "$INTERNET_PORTS" -lt 5 ]; then
        check_security "Port Security" "WARN" "Review recommended (Total: $PORT_COUNT, Public: $INTERNET_PORTS accessible ports): $PUBLIC_PORTS"
    else
        check_security "Port Security" "FAIL" "High exposure (Total: $PORT_COUNT, Public: $INTERNET_PORTS accessible ports): $PUBLIC_PORTS"
    fi
else
    check_security "Port Scanning" "WARN" "Port scanning failed due to missing tools. Ensure 'ss' or 'netstat' is installed."
fi

# Function to format the message with proper indentation for the report file
format_for_report() {
    local message="$1"
    echo "$message" >> "$REPORT_FILE"
}

# Check disk space usage
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print int($5)}')
if [ "$DISK_USAGE" -lt $RESOURCE_WARN ]; then
    check_security "Disk Usage" "PASS" "Healthy disk space available (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
elif [ "$DISK_USAGE" -lt $RESOURCE_FAIL ]; then
    check_security "Disk Usage" "WARN" "Disk space usage is moderate (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
else
    check_security "Disk Usage" "FAIL" "Critical disk space usage (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
fi

# Check memory usage
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $7}')
MEM_USAGE=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -lt $RESOURCE_WARN ]; then
    check_security "Memory Usage" "PASS" "Healthy memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
elif [ "$MEM_USAGE" -lt $RESOURCE_FAIL ]; then
    check_security "Memory Usage" "WARN" "Moderate memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
else
    check_security "Memory Usage" "FAIL" "Critical memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
fi

# Check CPU usage
CPU_CORES=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print int($8)}')
CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | tr -d ' ')
if [ "$CPU_USAGE" -lt $RESOURCE_WARN ]; then
    check_security "CPU Usage" "PASS" "Healthy CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
elif [ "$CPU_USAGE" -lt $RESOURCE_FAIL ]; then
    check_security "CPU Usage" "WARN" "Moderate CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
else
    check_security "CPU Usage" "FAIL" "Critical CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
fi

# Check sudo configuration
if grep -q "^Defaults.*logfile" "$SUDOERS_FILE"; then
    check_security "Sudo Logging" "PASS" "Sudo commands are being logged for audit purposes"
else
    check_security "Sudo Logging" "FAIL" "Sudo commands are not being logged - reduces audit capability"
fi

# Check password policy
if [ -f "$PASSWORD_QUALITY_CONF" ]; then
    # Extract the minlen value from pwquality.conf (last uncommented definition wins)
    MINLEN_VALUE=$(grep -E '^[[:space:]]*minlen[[:space:]]*=' "$PASSWORD_QUALITY_CONF" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -z "$MINLEN_VALUE" ]; then
        check_security "Password Policy" "FAIL" "No minlen set in $PASSWORD_QUALITY_CONF - system accepts weak passwords"
    elif ! [[ "$MINLEN_VALUE" =~ ^[0-9]+$ ]]; then
        check_security "Password Policy" "WARN" "Could not parse minlen value '$MINLEN_VALUE' in $PASSWORD_QUALITY_CONF"
    elif [ "$MINLEN_VALUE" -ge "$PASSWORD_MINLEN" ]; then
        check_security "Password Policy" "PASS" "Strong password policy is enforced (minlen=$MINLEN_VALUE)"
    else
        check_security "Password Policy" "FAIL" "Weak password policy - minlen=$MINLEN_VALUE is below the recommended $PASSWORD_MINLEN"
    fi
else
    check_security "Password Policy" "FAIL" "No password policy configured - system accepts weak passwords"
fi

# Check for suspicious SUID files
COMMON_SUID_PATHS='^/usr/bin/|^/bin/|^/sbin/|^/usr/sbin/|^/usr/lib|^/usr/libexec'
KNOWN_SUID_BINS='ping$|sudo$|mount$|umount$|su$|passwd$|chsh$|newgrp$|gpasswd$|chfn$'

SUID_FILES=$(find / -type f -perm -4000 2>/dev/null | \
    grep -v -E "$COMMON_SUID_PATHS" | \
    grep -v -E "$KNOWN_SUID_BINS" | \
    wc -l)

if [ "$SUID_FILES" -eq 0 ]; then
    check_security "SUID Files" "PASS" "No suspicious SUID files found - good security practice"
else
    check_security "SUID Files" "WARN" "Found $SUID_FILES SUID files outside standard locations - verify if legitimate"
fi

# Add system information summary to report
echo "================================" >> "$REPORT_FILE"
echo "System Information Summary:" >> "$REPORT_FILE"
echo "Hostname: $(hostname)" >> "$REPORT_FILE"
echo "Kernel: $(uname -r)" >> "$REPORT_FILE"
echo "OS: $(grep PRETTY_NAME "$OS_RELEASE_FILE" | cut -d'"' -f2)" >> "$REPORT_FILE"
echo "CPU Cores: $(nproc)" >> "$REPORT_FILE"
echo "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')" >> "$REPORT_FILE"
echo "Total Disk Space: $(df -h / | awk 'NR==2 {print $2}')" >> "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"

echo -e "\nVPS audit complete. Full report saved to $REPORT_FILE"
echo -e "Review $REPORT_FILE for detailed recommendations."

# Add summary to report
echo "================================" >> "$REPORT_FILE"
echo "End of VPS Audit Report" >> "$REPORT_FILE"
echo "Please review all failed checks and implement the recommended fixes." >> "$REPORT_FILE"

# If chown enabled, set ownership of report
if [ "$ENABLE_CHOWN" = true ]; then
    if ! chown "$REPORT_CHOWN_OWNER" "$REPORT_FILE"; then
        echo -e "${RED}[ERROR] Failed to change ownership of ${REPORT_FILE}." >&2
    fi
fi
