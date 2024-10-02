# Connectivity Test Package

## Overview

The Connectivity Test Package is a Debian-based solution designed to monitor network connectivity and local services. It provides automated checks and actions to maintain system stability and connectivity.

## Features

- Network connectivity monitoring
- Local service status checks
- Automatic service restart capabilities
- System reboot initiation (when necessary)
- Detailed logging with debug mode
- Configurable via a simple configuration file
- Runs as a systemd service

## Installation

1. Download the Debian package:
   ```
   wget ...
   ```

2. Install the package:
   ```
   sudo dpkg -i connectivity-test_0.0.1_all.deb
   ```

3. If there are any dependency issues, resolve them with:
   ```
   sudo apt-get install -f
   ```

## Configuration

The main configuration file is located at `/etc/connectivity_test.conf`. Modify this file to adjust the package's behavior:


## Development

### CI/CD

This project uses GitHub Actions for Continuous Integration and Deployment. The workflow includes:

- Linting the shell script using shellcheck
- Running tests using BATS
- Building the Debian package
- Uploading the package as a release asset when a new release is created

To run tests locally:

```
bats tests/connectivity_test.bats
```

To run linting locally:

```
shellcheck usr/bin/connectivity_test.sh
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure that your code passes all tests and linting before submitting a pull request.