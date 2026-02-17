#!/bin/bash
#
# Run Private LTE stack
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Default PlutoSDR IP
PLUTO_IP="${PLUTO_IP:-192.168.2.1}"

usage() {
    cat << EOF
Private LTE Run Script

Usage: $0 [OPTIONS] COMMAND

Commands:
  docker-combined   Run EPC + eNB in single Docker container (recommended)
  docker-separate   Run EPC and eNB in separate Docker containers
  native-epc        Run EPC natively (requires native build)
  native-enb        Run eNB natively (requires native build)
  native-all        Run EPC + eNB natively
  check-pluto       Check PlutoSDR connectivity
  shell             Start a shell in the Docker container

Options:
  -p, --pluto-ip IP  PlutoSDR IP address (default: 192.168.2.1)
  -h, --help         Show this help message

Examples:
  $0 docker-combined              # Run full stack in Docker
  $0 -p 192.168.1.100 native-all  # Run natively with custom Pluto IP
  $0 check-pluto                  # Verify PlutoSDR connection

EOF
}

check_pluto() {
    echo "Checking PlutoSDR at ${PLUTO_IP}..."

    if command -v iio_info &> /dev/null; then
        if iio_info -u ip:${PLUTO_IP} 2>/dev/null | grep -q "ad9361"; then
            echo "✓ PlutoSDR detected and responding"
            iio_info -u ip:${PLUTO_IP} 2>/dev/null | grep -E "(hw_model|fw_version)"
            return 0
        fi
    fi

    # Fallback: try ping
    if ping -c 1 -W 2 ${PLUTO_IP} &> /dev/null; then
        echo "✓ PlutoSDR is reachable at ${PLUTO_IP}"
        echo "  (Install iio_info for detailed hardware check)"
        return 0
    fi

    echo "✗ Cannot reach PlutoSDR at ${PLUTO_IP}"
    echo "  - Check USB/Ethernet connection"
    echo "  - Verify PlutoSDR is powered on"
    echo "  - Check network configuration"
    return 1
}

run_docker_combined() {
    echo "Starting Private LTE (Docker combined mode)..."
    cd "${PROJECT_DIR}"

    docker run --rm -it \
        --privileged \
        --network host \
        -v "${PROJECT_DIR}/configs:/etc/srsran:ro" \
        -e PLUTO_IP="${PLUTO_IP}" \
        pluto-lte:latest all
}

run_docker_separate() {
    echo "Starting Private LTE (Docker separate mode)..."
    cd "${PROJECT_DIR}"

    docker-compose up
}

run_native() {
    local component="$1"
    local prefix="${PREFIX:-/opt/pluto-lte}"

    # Source environment
    if [ -f /etc/profile.d/pluto-lte.sh ]; then
        source /etc/profile.d/pluto-lte.sh
    else
        export PATH="${prefix}/bin:${PATH}"
        export LD_LIBRARY_PATH="${prefix}/lib:${prefix}/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}"
    fi

    # Check binary exists
    if ! command -v srsenb &> /dev/null; then
        echo "Error: srsRAN binaries not found. Run build-native.sh first."
        exit 1
    fi

    # Ensure config directory exists
    if [ ! -d /etc/srsran ]; then
        echo "Setting up config directory..."
        sudo mkdir -p /etc/srsran
        sudo cp -r "${PROJECT_DIR}/configs/"* /etc/srsran/
    fi

    case "${component}" in
        epc)
            echo "Starting srsEPC..."
            sudo srsepc /etc/srsran/epc.conf
            ;;
        enb)
            echo "Starting srsENB..."
            # Update device_args with correct Pluto IP
            sudo sed -i "s/hostname=[0-9.]*,/hostname=${PLUTO_IP},/" /etc/srsran/enb.conf
            sudo srsenb /etc/srsran/enb.conf
            ;;
        all)
            echo "Starting srsEPC (background)..."
            sudo srsepc /etc/srsran/epc.conf &
            EPC_PID=$!
            sleep 3

            echo "Starting srsENB..."
            sudo sed -i "s/hostname=[0-9.]*,/hostname=${PLUTO_IP},/" /etc/srsran/enb.conf
            sudo srsenb /etc/srsran/enb.conf

            # Cleanup on exit
            trap "sudo kill ${EPC_PID} 2>/dev/null" EXIT
            ;;
    esac
}

run_shell() {
    cd "${PROJECT_DIR}"
    docker run --rm -it \
        --privileged \
        --network host \
        -v "${PROJECT_DIR}/configs:/etc/srsran:ro" \
        -e PLUTO_IP="${PLUTO_IP}" \
        pluto-lte:latest shell
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pluto-ip)
            PLUTO_IP="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        docker-combined)
            check_pluto || echo "Continuing anyway..."
            run_docker_combined
            exit 0
            ;;
        docker-separate)
            run_docker_separate
            exit 0
            ;;
        native-epc)
            run_native epc
            exit 0
            ;;
        native-enb)
            check_pluto || echo "Continuing anyway..."
            run_native enb
            exit 0
            ;;
        native-all)
            check_pluto || echo "Continuing anyway..."
            run_native all
            exit 0
            ;;
        check-pluto)
            check_pluto
            exit $?
            ;;
        shell)
            run_shell
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

usage
