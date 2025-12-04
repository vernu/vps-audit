#!/usr/bin/env bash

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

# Report Output Configuration

# Directory and File Naming
DEFAULT_REPORT_DIR="."   # Where reports will be saved
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILENAME="vps-audit-report-${TIMESTAMP}.txt"
REPORT_FILE="${DEFAULT_REPORT_DIR}/${REPORT_FILENAME}"

# Ownership
ENABLE_CHOWN=false  # Whether to apply chown to report directory
REPORT_CHOWN_OWNER="$(id -un):$(id -gn)"  # user:group - if running via sudo will default to root:root

# Ensure report directory exists
if [ ! -d "$DEFAULT_REPORT_DIR" ]; then
    if mkdir -p "$DEFAULT_REPORT_DIR"; then
        # Apply ownership only when directory was created
        if [ "$ENABLE_CHOWN" = true ]; then
            if ! chown -R "$REPORT_CHOWN_OWNER" "$DEFAULT_REPORT_DIR"; then
                echo -e "${RED}[ERROR] Failed to change ownership of ${DEFAULT_REPORT_DIR}." >&2
            fi
        fi
    else
        echo -e "${RED}[ERROR] Failed to create directory ${DEFAULT_REPORT_DIR}. Using current directory." >&2
        DEFAULT_REPORT_DIR="."
        REPORT_FILE="./${REPORT_FILENAME}"
        ENABLE_CHOWN=false
    fi
fi

# -----------------------------------------
# End Configuration
# -----------------------------------------


# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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
echo -e "${BLUE}${BOLD}VPS Security Audit Tool${NC}"
echo -e "${GRAY}https://github.com/vernu/vps-audit${NC}"
echo -e "${GRAY}Starting audit at $(date)${NC}\n"

echo "VPS Security Audit Tool" > "$REPORT_FILE"
echo "https://github.com/vernu/vps-audit" >> "$REPORT_FILE"
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

# Check failed login attempts
if [ -f "$AUTH_LOG_FILE" ]; then
    FAILED_LOGINS=$(grep -c "Failed password" "$AUTH_LOG_FILE" 2>/dev/null || echo 0)
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
    # Extract the minlen value from pwquality.conf
    MINLEN_VALUE=$(grep -E '^\s*minlen\s*=' "$PASSWORD_QUALITY_CONF" | awk -F= '{print $2}' | tr -d ' ')
    if [ "$MINLEN_VALUE" -ge 12 ]; then
        check_security "Password Policy" "PASS" "Strong password policy is enforced"
    else
        check_security "Password Policy" "FAIL" "Weak password policy - passwords may be too simple"
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
echo -e "Review $REPORT_FILENAME for detailed recommendations."

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