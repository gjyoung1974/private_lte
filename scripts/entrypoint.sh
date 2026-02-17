#!/bin/bash
set -e

PREFIX=/opt/pluto-lte
CONFIG_DIR=/etc/srsran

# Export library paths
export LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}
export PATH=${PREFIX}/bin:${PATH}

# Check for PlutoSDR connectivity
check_pluto() {
    echo "Checking PlutoSDR connectivity..."
    if iio_info -u ip:${PLUTO_IP:-192.168.2.1} 2>/dev/null | grep -q "ad9361"; then
        echo "PlutoSDR detected at ${PLUTO_IP:-192.168.2.1}"
        return 0
    else
        echo "Warning: PlutoSDR not detected at ${PLUTO_IP:-192.168.2.1}"
        return 1
    fi
}

# Setup network for EPC
setup_network() {
    echo "Setting up network configuration..."

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

    # Setup NAT for UE internet access (if running EPC)
    if [[ "$1" == "srsepc" ]] || [[ "$1" == "all" ]]; then
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
        echo "NAT configured for UE internet access"
    fi
}

# Run component based on argument
case "$1" in
    srsenb)
        echo "Starting srsENB (eNodeB)..."
        check_pluto || echo "Continuing anyway..."
        exec srsenb ${CONFIG_DIR}/enb.conf
        ;;
    srsepc)
        echo "Starting srsEPC (Core Network)..."
        setup_network srsepc
        exec srsepc ${CONFIG_DIR}/epc.conf
        ;;
    srsue)
        echo "Starting srsUE (User Equipment)..."
        check_pluto || echo "Continuing anyway..."
        exec srsue ${CONFIG_DIR}/ue.conf
        ;;
    all)
        echo "Starting full LTE stack (EPC + eNB)..."
        check_pluto || echo "Continuing anyway..."
        setup_network all

        # Start EPC in background
        srsepc ${CONFIG_DIR}/epc.conf &
        EPC_PID=$!
        sleep 2

        # Start eNB in foreground
        srsenb ${CONFIG_DIR}/enb.conf &
        ENB_PID=$!

        # Wait for any process to exit
        wait -n

        # Cleanup
        kill $EPC_PID $ENB_PID 2>/dev/null || true
        ;;
    shell)
        echo "Starting shell..."
        exec /bin/bash
        ;;
    *)
        echo "Usage: $0 {srsenb|srsepc|srsue|all|shell}"
        echo ""
        echo "Commands:"
        echo "  srsenb  - Start the eNodeB (base station)"
        echo "  srsepc  - Start the EPC (core network)"
        echo "  srsue   - Start the UE (user equipment)"
        echo "  all     - Start EPC and eNB together"
        echo "  shell   - Start a bash shell"
        exit 1
        ;;
esac
