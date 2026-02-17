# Private LTE with PlutoPlus SDR for Raspberry Pi 5
# Based on: https://www.quantulum.co.uk/blog/private-lte-with-plutoplus-sdr

FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG PREFIX=/opt/pluto-lte
ARG JOBS=4

# Install base build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    pkg-config \
    ca-certificates \
    wget \
    # LibIIO dependencies
    libxml2-dev \
    bison \
    flex \
    libcdk5-dev \
    libusb-1.0-0-dev \
    libaio-dev \
    libavahi-client-dev \
    libavahi-common-dev \
    # SoapySDR dependencies
    g++ \
    libpython3-dev \
    python3-dev \
    python3-distutils \
    python3-numpy \
    swig \
    # srsRAN dependencies
    libfftw3-dev \
    libmbedtls-dev \
    libboost-program-options-dev \
    libconfig++-dev \
    libsctp-dev \
    libzmq3-dev \
    libboost-system-dev \
    libboost-thread-dev \
    libboost-test-dev \
    libyaml-cpp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 1. Build SoapySDR (v0.8.1)
RUN git clone --depth 1 --branch soapy-sdr-0.8.1 https://github.com/pothosware/SoapySDR.git && \
    cd SoapySDR && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
          -DCMAKE_BUILD_TYPE=Release \
          .. && \
    make -j${JOBS} && \
    make install

# Set up environment for subsequent builds
ENV PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib/aarch64-linux-gnu/pkgconfig
ENV CMAKE_PREFIX_PATH=${PREFIX}
ENV LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu
ENV PATH=${PREFIX}/bin:${PATH}

# 2. Build LibIIO (v0.24+)
RUN git clone --depth 1 --branch v0.25 https://github.com/analogdevicesinc/libiio.git && \
    cd libiio && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
          -DCMAKE_BUILD_TYPE=Release \
          -DWITH_SERIAL_BACKEND=OFF \
          -DPYTHON_BINDINGS=OFF \
          .. && \
    make -j${JOBS} && \
    make install

# 3. Build LibAD9361-IIO (v0.3)
RUN git clone --depth 1 --branch v0.3 https://github.com/analogdevicesinc/libad9361-iio.git && \
    cd libad9361-iio && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
          -DCMAKE_BUILD_TYPE=Release \
          -DLIBIIO_INCLUDEDIR=${PREFIX}/include \
          -DLIBIIO_LIBRARIES=${PREFIX}/lib/libiio.so \
          .. && \
    make -j${JOBS} && \
    make install

# 4. Build SoapyPlutoSDR (with timestamping support)
RUN git clone https://github.com/pothosware/SoapyPlutoSDR.git && \
    cd SoapyPlutoSDR && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
          -DCMAKE_BUILD_TYPE=Release \
          -DSoapySDR_DIR=${PREFIX}/lib/cmake/SoapySDR \
          .. && \
    make -j${JOBS} && \
    make install

# 5. Build srsRAN 4G (release_23_04)
RUN git clone --depth 1 --branch release_23_04 https://github.com/srsran/srsRAN_4G.git && \
    cd srsRAN_4G && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
          -DCMAKE_BUILD_TYPE=Release \
          -DUSE_LTE_RATES=ON \
          -DENABLE_SRSUE=ON \
          -DENABLE_SRSENB=ON \
          -DENABLE_SRSEPC=ON \
          .. && \
    make -j${JOBS} && \
    make install

# Test stage - validates binaries work before producing final image
FROM debian:bookworm-slim AS test

ARG DEBIAN_FRONTEND=noninteractive
ARG PREFIX=/opt/pluto-lte

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libusb-1.0-0 \
    libaio1 \
    libavahi-client3 \
    libfftw3-double3 \
    libfftw3-single3 \
    libmbedtls14 \
    libmbedcrypto7 \
    libmbedx509-1 \
    libboost-program-options1.74.0 \
    libconfig++9v5 \
    libsctp1 \
    libzmq5 \
    libboost-system1.74.0 \
    libboost-thread1.74.0 \
    libyaml-cpp0.7 \
    python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder ${PREFIX} ${PREFIX}
ENV PATH=${PREFIX}/bin:${PATH}
ENV LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu

RUN echo "=== Testing srsRAN binaries ===" && \
    # Verify binaries exist
    test -x ${PREFIX}/bin/srsenb && \
    test -x ${PREFIX}/bin/srsepc && \
    test -x ${PREFIX}/bin/srsue && \
    test -x ${PREFIX}/bin/SoapySDRUtil && \
    echo "PASS: all binaries present and executable" && \
    # Verify srsenb runs and reports correct version
    srsenb --version 2>&1 | grep -q "Version 23.4.0" && \
    echo "PASS: srsenb version 23.4.0" && \
    # Verify srsue runs and reports correct version
    srsue --version 2>&1 | grep -q "Version 23.4.0" && \
    echo "PASS: srsue version 23.4.0" && \
    # Verify srsenb loads RF plugins (SoapySDR + ZMQ)
    srsenb --version 2>&1 | grep -q "libsrsran_rf_soapy.so" && \
    echo "PASS: srsenb soapy RF plugin loaded" && \
    srsenb --version 2>&1 | grep -q "libsrsran_rf_zmq.so" && \
    echo "PASS: srsenb zmq RF plugin loaded" && \
    # Verify SoapySDR finds PlutoSDR module
    SoapySDRUtil --info 2>&1 | grep -q "libPlutoSDRSupport.so" && \
    echo "PASS: SoapySDR PlutoSDR module found" && \
    # Verify no missing shared libraries
    ! ldd ${PREFIX}/bin/srsenb 2>&1 | grep -q "not found" && \
    echo "PASS: srsenb has no missing shared libraries" && \
    ! ldd ${PREFIX}/bin/srsepc 2>&1 | grep -q "not found" && \
    echo "PASS: srsepc has no missing shared libraries" && \
    ! ldd ${PREFIX}/bin/srsue 2>&1 | grep -q "not found" && \
    echo "PASS: srsue has no missing shared libraries" && \
    echo "=== All tests passed ==="

# Runtime image
FROM debian:bookworm-slim AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG PREFIX=/opt/pluto-lte

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libusb-1.0-0 \
    libaio1 \
    libavahi-client3 \
    libfftw3-double3 \
    libfftw3-single3 \
    libmbedtls14 \
    libmbedcrypto7 \
    libmbedx509-1 \
    libboost-program-options1.74.0 \
    libconfig++9v5 \
    libsctp1 \
    libzmq5 \
    libboost-system1.74.0 \
    libboost-thread1.74.0 \
    libyaml-cpp0.7 \
    python3 \
    iproute2 \
    iptables \
    net-tools \
    iputils-ping \
    tcpdump \
    && rm -rf /var/lib/apt/lists/*

# Copy built artifacts (from test stage, which forces tests to pass first)
COPY --from=test ${PREFIX} ${PREFIX}

# Set up environment
ENV PATH=${PREFIX}/bin:${PATH}
ENV LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib/aarch64-linux-gnu

# Create config directory
RUN mkdir -p /etc/srsran

# Copy default configs
COPY configs/ /etc/srsran/

# Expose ports for EPC
EXPOSE 2152/udp
EXPOSE 36412/sctp

# Create entrypoint script
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["srsenb"]
