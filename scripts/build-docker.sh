#!/bin/bash
#
# Build Docker image for Private LTE on Raspberry Pi 5
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

cd "${PROJECT_DIR}"

echo "=============================================="
echo "Building Private LTE Docker Image"
echo "=============================================="
echo "This may take 30-60 minutes on Raspberry Pi 5"
echo "=============================================="

# Check if running on ARM64
ARCH=$(uname -m)
if [[ "${ARCH}" != "aarch64" ]]; then
    echo "Warning: Building on ${ARCH}, image is optimized for aarch64 (Raspberry Pi 5)"
    echo "Consider using: docker buildx build --platform linux/arm64 ..."
fi

# Build the image
docker build \
    --tag pluto-lte:latest \
    --build-arg JOBS=$(nproc) \
    --progress=plain \
    .

echo ""
echo "=============================================="
echo "Build complete! Running post-build tests..."
echo "=============================================="

# Post-build smoke tests against the final image
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

DOCKER_RUN="docker run --rm --entrypoint= pluto-lte:latest"

run_test "srsenb is executable"  ${DOCKER_RUN} test -x /opt/pluto-lte/bin/srsenb
run_test "srsepc is executable"  ${DOCKER_RUN} test -x /opt/pluto-lte/bin/srsepc
run_test "srsue is executable"   ${DOCKER_RUN} test -x /opt/pluto-lte/bin/srsue
run_test "srsenb version 23.4.0" ${DOCKER_RUN} bash -c "srsenb --version 2>&1 | grep -q 'Version 23.4.0'"
run_test "srsue version 23.4.0"  ${DOCKER_RUN} bash -c "srsue --version 2>&1 | grep -q 'Version 23.4.0'"
run_test "soapy RF plugin loaded" ${DOCKER_RUN} bash -c "srsenb --version 2>&1 | grep -q 'libsrsran_rf_soapy.so'"
run_test "zmq RF plugin loaded"   ${DOCKER_RUN} bash -c "srsenb --version 2>&1 | grep -q 'libsrsran_rf_zmq.so'"
run_test "PlutoSDR module found"  ${DOCKER_RUN} bash -c "SoapySDRUtil --info 2>&1 | grep -q 'libPlutoSDRSupport.so'"
run_test "srsenb no missing libs" ${DOCKER_RUN} bash -c "! ldd /opt/pluto-lte/bin/srsenb 2>&1 | grep -q 'not found'"
run_test "srsepc no missing libs" ${DOCKER_RUN} bash -c "! ldd /opt/pluto-lte/bin/srsepc 2>&1 | grep -q 'not found'"
run_test "srsue no missing libs"  ${DOCKER_RUN} bash -c "! ldd /opt/pluto-lte/bin/srsue 2>&1 | grep -q 'not found'"

echo ""
echo "=============================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=============================================="

if [ "${FAIL}" -ne 0 ]; then
    echo "ERROR: Some post-build tests failed!"
    exit 1
fi

echo ""
echo "Image: pluto-lte:latest"
echo ""
echo "To run:"
echo "  docker-compose up -d        # Separate EPC + eNB"
echo "  docker-compose --profile combined up -d  # Combined mode"
echo ""
echo "Or manually:"
echo "  docker run --rm -it --privileged --network host pluto-lte:latest all"
echo "=============================================="
