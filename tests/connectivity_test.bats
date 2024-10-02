#!/usr/bin/env bats

# Setup function to create temporary files and directories
setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    export TEST_CONFIG_FILE="${TEST_DIR}/connectivity_test.conf"
    export TEST_LOG_FILE="${TEST_DIR}/connectivity_test.log"
    export TEST_DEBUG_LOG_FILE="${TEST_DIR}/connectivity_test_debug.log"
    
    # Create a mock configuration file
    cat << EOF > "$TEST_CONFIG_FILE"
ips=("127.0.0.1:ping")
threshold=1
interval=300
timeout=30
debug=true
local_services=("ssh:port:22")
EOF
    
    # Copy the original script to the test directory
    cp usr/local/bin/connectivity_test.sh "${TEST_DIR}/connectivity_test.sh"
    chmod +x "${TEST_DIR}/connectivity_test.sh"
}

# Teardown function to clean up temporary files
teardown() {
    rm -rf "$TEST_DIR"
}

@test "connectivity_test.sh exists and is executable" {
  run test -x usr/local/bin/connectivity_test.sh
  [ "$status" -eq 0 ]
}

@test "configuration file exists" {
  run test -f "$TEST_CONFIG_FILE"
  [ "$status" -eq 0 ]
}

@test "log_message function works" {
  source "${TEST_DIR}/connectivity_test.sh"
  run log_message "INFO" "Test message"
  [ "$status" -eq 0 ]
  [ -f "$TEST_LOG_FILE" ]
  run grep "INFO - Test message" "$TEST_LOG_FILE"
  [ "$status" -eq 0 ]
}
