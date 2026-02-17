#!/bin/bash
#
# Native build script for Private LTE on Raspberry Pi 5
# Based on: https://www.quantulum.co.uk/blog/private-lte-with-plutoplus-sdr
#
set -e

PREFIX="${PREFIX:-/opt/pluto-lte}"
JOBS="${JOBS:-4}"
BUILD_DIR="${BUILD_DIR:-/tmp/pluto-lte-build}"

echo "=============================================="
echo "Private LTE Build Script for Raspberry Pi 5"
echo "=============================================="
echo "Install prefix: ${PREFIX}"
echo "Build directory: ${BUILD_DIR}"
echo "Parallel jobs: ${JOBS}"
echo "=============================================="

# Check if running as root for installation
if [ "$EUID" -ne 0 ] && [ ! -w "${PREFIX}" ]; then
    echo "Warning: May need sudo for installation to ${PREFIX}"
fi

# Create directories
mkdir -p "${BUILD_DIR}"
mkdir -p "${PREFIX}"

# Install dependencies
install_dependencies() {
    echo "[1/6] Installing build dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        cmake \
        git \
        pkg-config \
        libxml2-dev \
        bison \
        flex \
        libcdk5-dev \
        libusb-1.0-0-dev \
        libaio-dev \
        libavahi-client-dev \
        g++ \
        libpython3-dev \
        python3-numpy \
        swig \
        libfftw3-dev \
        libmbedtls-dev \
        libboost-program-options-dev \
        libconfig++-dev \
        libsctp-dev \
        libzmq3-dev \
        libboost-system-dev \
        libboost-thread-dev \
        libboost-test-dev \
        libyaml-cpp-dev
}

# Build SoapySDR
build_soapysdr() {
    echo "[2/6] Building SoapySDR v0.8.1..."
    cd "${BUILD_DIR}"
    if [ ! -d "SoapySDR" ]; then
        git clone --depth 1 --branch soapy-sdr-0.8.1 https://github.com/pothosware/SoapySDR.git
    fi
    cd SoapySDR
    rm -rf build && mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DCMAKE_BUILD_TYPE=Release \
          ..
    make -j${JOBS}
    sudo make install
}

# Build LibIIO
build_libiio() {
    echo "[3/6] Building LibIIO v0.25..."
    cd "${BUILD_DIR}"
    if [ ! -d "libiio" ]; then
        git clone --depth 1 --branch v0.25 https://github.com/analogdevicesinc/libiio.git
    fi
    cd libiio
    rm -rf build && mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DCMAKE_BUILD_TYPE=Release \
          -DWITH_SERIAL_BACKEND=OFF \
          -DPYTHON_BINDINGS=OFF \
          ..
    make -j${JOBS}
    sudo make install
}

# Build LibAD9361
build_libad9361() {
    echo "[4/6] Building LibAD9361-IIO v0.3..."
    cd "${BUILD_DIR}"
    if [ ! -d "libad9361-iio" ]; then
        git clone --depth 1 --branch v0.3 https://github.com/analogdevicesinc/libad9361-iio.git
    fi
    cd libad9361-iio
    rm -rf build && mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DCMAKE_BUILD_TYPE=Release \
          -DLIBIIO_INCLUDEDIR="${PREFIX}/include" \
          -DLIBIIO_LIBRARIES="${PREFIX}/lib/libiio.so" \
          ..
    make -j${JOBS}
    sudo make install
}

# Build SoapyPlutoSDR
build_soapyplutosdr() {
    echo "[5/6] Building SoapyPlutoSDR..."
    cd "${BUILD_DIR}"
    if [ ! -d "SoapyPlutoSDR" ]; then
        git clone https://github.com/pothosware/SoapyPlutoSDR.git
    fi
    cd SoapyPlutoSDR
    rm -rf build && mkdir build && cd build

    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/aarch64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"
    export CMAKE_PREFIX_PATH="${PREFIX}"

    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DCMAKE_BUILD_TYPE=Release \
          -DSoapySDR_DIR="${PREFIX}/lib/cmake/SoapySDR" \
          ..
    make -j${JOBS}
    sudo make install
}

# Build srsRAN
build_srsran() {
    echo "[6/6] Building srsRAN 4G (release_23_04)..."
    cd "${BUILD_DIR}"
    if [ ! -d "srsRAN_4G" ]; then
        git clone --depth 1 --branch release_23_04 https://github.com/srsran/srsRAN_4G.git
    fi
    cd srsRAN_4G
    rm -rf build && mkdir build && cd build

    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/aarch64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"
    export CMAKE_PREFIX_PATH="${PREFIX}"

    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DCMAKE_BUILD_TYPE=Release \
          -DUSE_LTE_RATES=ON \
          -DENABLE_SRSUE=ON \
          -DENABLE_SRSENB=ON \
          -DENABLE_SRSEPC=ON \
          ..
    make -j${JOBS}
    sudo make install
}

# Setup environment
setup_environment() {
    echo "Setting up environment..."

    # Create environment file
    cat > /tmp/pluto-lte-env.sh << EOF
# PlutoLTE Environment
export PATH="${PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/aarch64-linux-gnu/pkgconfig:\${PKG_CONFIG_PATH}"
EOF

    sudo mv /tmp/pluto-lte-env.sh /etc/profile.d/pluto-lte.sh
    sudo chmod 644 /etc/profile.d/pluto-lte.sh

    # Update ldconfig
    echo "${PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/pluto-lte.conf
    echo "${PREFIX}/lib/aarch64-linux-gnu" | sudo tee -a /etc/ld.so.conf.d/pluto-lte.conf
    sudo ldconfig

    echo "Environment configured. Please run: source /etc/profile.d/pluto-lte.sh"
}

# Verify installation
verify_install() {
    echo "=============================================="
    echo "Verifying installation..."
    echo "=============================================="

    export PATH="${PREFIX}/bin:${PATH}"
    export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}"

    PASS=0
    FAIL=0

    run_test() {
        local desc="$1"
        shift
        if "$@" > /dev/null 2>&1; then
            echo "  PASS: ${desc}"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: ${desc}"
            FAIL=$((FAIL + 1))
        fi
    }

    # Binaries exist and are executable
    run_test "srsenb is executable" test -x "${PREFIX}/bin/srsenb"
    run_test "srsepc is executable" test -x "${PREFIX}/bin/srsepc"
    run_test "srsue is executable"  test -x "${PREFIX}/bin/srsue"
    run_test "SoapySDRUtil is executable" test -x "${PREFIX}/bin/SoapySDRUtil"

    # Version checks
    run_test "srsenb version 23.4.0" bash -c "srsenb --version 2>&1 | grep -q 'Version 23.4.0'"
    run_test "srsue version 23.4.0"  bash -c "srsue --version 2>&1 | grep -q 'Version 23.4.0'"

    # RF plugin checks
    run_test "srsenb soapy RF plugin loaded" bash -c "srsenb --version 2>&1 | grep -q 'libsrsran_rf_soapy.so'"
    run_test "srsenb zmq RF plugin loaded"   bash -c "srsenb --version 2>&1 | grep -q 'libsrsran_rf_zmq.so'"

    # SoapySDR module check
    run_test "SoapySDR PlutoSDR module found" bash -c "SoapySDRUtil --info 2>&1 | grep -q 'libPlutoSDRSupport.so'"

    # Shared library checks
    run_test "srsenb has no missing libraries" bash -c "! ldd ${PREFIX}/bin/srsenb 2>&1 | grep -q 'not found'"
    run_test "srsepc has no missing libraries" bash -c "! ldd ${PREFIX}/bin/srsepc 2>&1 | grep -q 'not found'"
    run_test "srsue has no missing libraries"  bash -c "! ldd ${PREFIX}/bin/srsue 2>&1 | grep -q 'not found'"

    echo "=============================================="
    echo "Results: ${PASS} passed, ${FAIL} failed"
    echo "=============================================="

    if [ "${FAIL}" -ne 0 ]; then
        echo "ERROR: Some tests failed!"
        return 1
    fi
}

# Main build sequence
main() {
    case "${1:-all}" in
        deps)
            install_dependencies
            ;;
        soapysdr)
            build_soapysdr
            ;;
        libiio)
            build_libiio
            ;;
        libad9361)
            build_libad9361
            ;;
        soapypluto)
            build_soapyplutosdr
            ;;
        srsran)
            build_srsran
            ;;
        env)
            setup_environment
            ;;
        test)
            verify_install
            ;;
        all)
            install_dependencies
            build_soapysdr
            build_libiio
            build_libad9361
            build_soapyplutosdr
            build_srsran
            setup_environment
            verify_install
            echo ""
            echo "=============================================="
            echo "Build complete!"
            echo "=============================================="
            echo "Binaries installed to: ${PREFIX}/bin"
            echo ""
            echo "Next steps:"
            echo "  1. source /etc/profile.d/pluto-lte.sh"
            echo "  2. Copy configs to /etc/srsran/"
            echo "  3. Connect PlutoPlus SDR"
            echo "  4. Run: srsepc /etc/srsran/epc.conf &"
            echo "  5. Run: srsenb /etc/srsran/enb.conf"
            echo "=============================================="
            ;;
        *)
            echo "Usage: $0 {all|deps|soapysdr|libiio|libad9361|soapypluto|srsran|env|test}"
            exit 1
            ;;
    esac
}

main "$@"
