#!/bin/bash

# Connectivity Test Script
# ------------------------
# This script monitors network connectivity to specified IP addresses and
# local services. It can initiate a system reboot if network connectivity 
# falls below a defined threshold and restart local services if they're not responding.
#
# Usage:
#   This script is intended to be run as a systemd service.
#   Manual execution: /etc/connectivity_test/connectivity_test.sh [options]
#
# Options:
#   -h, --help     Show this help message and exit
#   -c, --config   Specify an alternate config file (default: /etc/connectivity_test/connectivity_test.conf)
#
# Configuration:
#   The script reads its configuration from /etc/connectivity_test/connectivity_test.conf
#   See that file for details on configurable parameters.
#
# Logs:
#   Main log: /var/log/connectivity_test.log
#   Debug log: /var/log/connectivity_test_debug.log (when debug mode is enabled)

set -euo pipefail

# Log file locations
log_file="${TEST_LOG_FILE:-/var/log/connectivity_test.log}"
debug_log_file="${TEST_DEBUG_LOG_FILE:-/var/log/connectivity_test_debug.log}"

# Initialize local_services as an empty array
local_services=()

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -h, --help     Show this help message and exit
  -c, --config   Specify an alternate config file (default: /etc/connectivity_test/connectivity_test.conf)

This script monitors network connectivity and local services. It can initiate a system reboot if 
network connectivity falls below a threshold and restart local services if they're not responding.
It is designed to be run as a systemd service but can be executed manually for testing purposes.

For full documentation, please refer to the comments at the beginning of this script.
EOF
}

# Parse command line arguments
config_file="${TEST_CONFIG_FILE:-/etc/connectivity_test.conf}"
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--config)
            config_file="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $message" >> "$log_file"
}

log_debug() {
    if [[ "${debug:-false}" == "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG - $1" >> "$debug_log_file"
    fi
}

# Function to validate configuration
validate_config() {
    local error=false
    if [[ -z "${ips[*]:-}" ]]; then
        log_message "ERROR" "No IP addresses specified in configuration"
        error=true
    fi
    if [[ -z "${threshold:-}" ]]; then
        log_message "ERROR" "Threshold not specified in configuration"
        error=true
    fi
    if [[ -z "${interval:-}" ]]; then
        log_message "ERROR" "Interval not specified in configuration"
        error=true
    fi
    if [[ -z "${timeout:-}" ]]; then
        log_message "ERROR" "Timeout not specified in configuration"
        error=true
    fi
    if [[ "$error" == "true" ]]; then
        return 1
    fi
}

# Function to load configuration
load_config() {
    if [ ! -f "$config_file" ]; then
        log_message "ERROR" "Configuration file not found: $config_file"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$config_file"
    if ! validate_config; then
        log_message "ERROR" "Invalid configuration"
        exit 1
    fi
}

# Variables for statistics
iteration_count=0
total_reachable_count=0

# Function to reload configuration
reload_config() {
    log_message "INFO" "Reloading configuration..."
    load_config
    log_message "INFO" "Configuration reloaded"
}

# Function to check connectivity to an IP address
check_connectivity() {
    local target=$1
    local ip
    local method
    local port

    IFS=':' read -r ip method port <<< "$target"

    case $method in
        ping)
            if ping -c 1 -W 2 "$ip" > /dev/null 2>&1; then
                log_debug "$ip is reachable via ping"
                return 0  # Success
            else
                log_debug "$ip is unreachable via ping"
                return 1  # Failure
            fi
            ;;
        http|https)
            local url="${method}://${ip}:${port:-80}"
            if curl -s --head --request GET "$url" --connect-timeout 2 | grep "HTTP/" > /dev/null 2>&1; then
                log_debug "$url is reachable"
                return 0  # Success
            else
                log_debug "$url is unreachable"
                return 1  # Failure
            fi
            ;;
        *)
            log_message "ERROR" "Unknown connectivity check method: $method"
            return 1  # Failure
            ;;
    esac
}

# Function to check local service
check_local_service() {
    local service=$1
    local check_type=$2
    local port=$3

    case $check_type in
        process)
            if pgrep -x "$service" > /dev/null; then
                log_debug "Service $service is running"
                return 0  # Success
            else
                log_debug "Service $service is not running"
                return 1  # Failure
            fi
            ;;
        port)
            if nc -z localhost "$port"; then
                log_debug "Port $port for service $service is open"
                return 0  # Success
            else
                log_debug "Port $port for service $service is closed"
                return 1  # Failure
            fi
            ;;
        *)
            log_message "ERROR" "Unknown check type for service $service: $check_type"
            return 1  # Failure
            ;;
    esac
}

# Function to perform or simulate reboot
perform_reboot() {
    if [[ "${debug:-false}" == "true" ]]; then
        log_message "DEBUG" "SIMULATED REBOOT: System would reboot here if not in debug mode"
    else
        log_message "INFO" "Rebooting..."
        sudo /sbin/reboot
    fi
}

# Function to perform or simulate service restart
restart_service() {
    local service=$1
    log_message "WARNING" "Attempting to restart service: $service"
    if [[ "${debug:-false}" == "true" ]]; then
        log_message "DEBUG" "SIMULATED RESTART: Would restart $service if not in debug mode"
        return 0
    else
        if sudo systemctl restart "$service"; then
            log_message "INFO" "Successfully restarted service: $service"
            return 0
        else
            log_message "ERROR" "Failed to restart service: $service"
            return 1
        fi
    fi
}

# Function for graceful shutdown
graceful_shutdown() {
    log_message "INFO" "Received shutdown signal. Exiting..."
    exit 0
}

# Set up signal handlers
trap reload_config SIGHUP
trap graceful_shutdown SIGTERM SIGINT

# Only load config and run main logic if not being sourced (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Load configuration initially
    load_config

    # Log service startup
    log_message "INFO" "Connectivity Test service started"
    log_debug "Configuration loaded: ips=${ips[*]}, threshold=$threshold, interval=$interval, timeout=$timeout, debug=${debug:-false}"

    log_message "INFO" "Entering main loop"
    log_debug "Interval: $interval seconds"

    # Main loop
    while true; do
        ((iteration_count++))
        start_time=$(date +%s)
        
        log_message "INFO" "Starting iteration $iteration_count"
        
        reachable_count=0
        for target in "${ips[@]}"; do
            if check_connectivity "$target"; then
                ((reachable_count++))
            else
                log_message "WARNING" "Lost connection to $target"
            fi
        done

        # Check local services
        if [ ${#local_services[@]} -gt 0 ]; then
            for service in "${local_services[@]}"; do
                IFS=':' read -r service_name check_type port <<< "$service"
                if ! check_local_service "$service_name" "$check_type" "$port"; then
                    log_message "WARNING" "Service $service_name is not responding"
                    restart_service "$service_name"
                fi
            done
        fi

        total_reachable_count=$((total_reachable_count + reachable_count))
        average_reachable=$(bc <<< "scale=2; $total_reachable_count / $iteration_count")

        log_message "INFO" "Iteration $iteration_count: $reachable_count/${#ips[@]} devices reachable"
        log_debug "Average reachable devices: $average_reachable"

        if [[ $reachable_count -lt $threshold ]]; then
            log_message "WARNING" "Less than $threshold devices are reachable"

            if [[ "${debug:-false}" == "true" ]]; then
                log_message "DEBUG" "SIMULATED USER PROMPT: Would ask for reboot confirmation if not in debug mode"
                perform_reboot
            else
                # Broadcast message to all users
                message="Less than $threshold devices are reachable. Reboot now? (Press N within $timeout seconds to cancel)"
                echo "$message" | wall

                # Read user input with timeout
                if ! read -r -t "$timeout" -n 1 response; then
                    response=""
                fi
                echo

                if [[ $response != "N" && $response != "n" ]]; then
                    perform_reboot
                else
                    log_message "INFO" "Reboot cancelled."
                fi
            fi
        fi

        end_time=$(date +%s)
        iteration_duration=$((end_time - start_time))
        log_debug "Iteration duration: $iteration_duration seconds"

        sleep_duration=$((interval - iteration_duration))
        if [[ $sleep_duration -gt 0 ]]; then
            log_debug "Sleeping for $sleep_duration seconds"
            sleep "$sleep_duration"
        else
            log_message "WARNING" "Iteration took longer than the specified interval"
        fi

        log_debug "Woke up from sleep"
    done
fi