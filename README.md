# Private LTE with PlutoPlus SDR on Raspberry Pi 5

Build scripts and Docker configuration for running a private LTE network using
[PlutoPlus SDR](https://github.com/plutoplus/plutoplus) and srsRAN on Raspberry Pi 5.
- Based on: https://www.quantulum.co.uk/blog/private-lte-with-plutoplus-sdr

## Prerequisites

- Raspberry Pi 5 (4GB+ RAM recommended)
- [PlutoPlus SDR](https://github.com/plutoplus/plutoplus) with custom firmware (timestamping support)
- Docker and Docker Compose (for containerized deployment)
- Programmable USIM cards (e.g., sysmoISIM-SJA5) with matching IMSI/Ki/OPc values
- USB smart card reader for SIM programming (e.g., Omnikey 3121)
- Unlocked phones with Band 13 support (all Verizon phones)

## Quick Start (Docker)

```bash
# Build the Docker image (takes 30-60 minutes)
./scripts/build-docker.sh

# Check PlutoSDR connectivity
./scripts/run.sh check-pluto

# Run the full LTE stack
./scripts/run.sh docker-combined
```

## Quick Start (Native)

```bash
# Build all components natively
./scripts/build-native.sh all

# Source the environment
source /etc/profile.d/pluto-lte.sh

# Copy configs
sudo mkdir -p /etc/srsran
sudo cp configs/* /etc/srsran/

# Run the stack
./scripts/run.sh native-all
```

## Configuration

This network is configured for **Band 13 (700 MHz)**, Verizon's primary LTE band.
All Verizon-sold phones support Band 13, making it the best choice for using
US Verizon handsets on a private LTE network.

### Network Identity (PLMN)

The MCC/MNC values must match across all three places:

| File | Fields | Current Value |
|------|--------|---------------|
| `configs/enb.conf` | `mcc`, `mnc` | `001` / `01` |
| `configs/epc.conf` | `mcc`, `mnc` | `001` / `01` |
| `configs/user_db.csv` | IMSI prefix | `00101` |

`001/01` is a test PLMN, suitable for lab and development use. If you change
the MCC/MNC, you must update all three files **and** reprogram your SIM cards
to match (see [Programming SIM Cards](#programming-sim-cards-with-pysim)).

### PlutoSDR Network Setup

Configure your PlutoSDR with a static IP via its `config.txt`:

```
[USB_ETHERNET]
ipaddr_eth = 192.168.2.1
netmask_eth = 255.255.255.0
```

### eNodeB Configuration (`configs/enb.conf`)

#### Cell & RF Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `dl_earfcn` | `5230` | Band 13 downlink center (751 MHz) |
| `n_prb` | `25` | 5 MHz bandwidth (25 resource blocks). Band 13 is 10 MHz wide, so `50` PRBs is possible if the SDR/CPU can handle it. |
| `tx_gain` | `89` | Transmit gain (dB). Near max for PlutoPlus. Reduce for close-range testing. |
| `rx_gain` | `20` | Receive gain (dB). Increase if UEs have trouble attaching. |
| `pci` | `1` | Physical Cell Identity (0-503). Only matters if running multiple cells. |
| `tac` | `0x0007` | Tracking Area Code. Must match `epc.conf`. |

#### SDR Connection

The `device_args` line controls how srsRAN talks to the PlutoPlus:

```ini
device_args = driver=plutosdr,hostname=192.168.2.1,direct=1,timestamp_every=5760,loopback=0
```

- `hostname=192.168.2.1` - PlutoSDR IP address (USB default)
- `direct=1` - Bypass RF switch matrix for lower latency
- `timestamp_every=5760` - IQ timestamp interval (critical for sync)
- `loopback=0` - Disable internal loopback (set to `1` for testing without antenna)

### EPC Configuration (`configs/epc.conf`)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `mcc` / `mnc` | `001` / `01` | Must match `enb.conf` |
| `tac` | `0x0007` | Must match `enb.conf` |
| `apn` | `internet` | Access Point Name. Phones must be configured with this APN. |
| `dns_addr` | `8.8.8.8` | DNS server pushed to UEs |
| `encryption_algo` | `EEA0` | No encryption (simplest). Use `EEA2` (AES) for security. |
| `integrity_algo` | `EIA1` | SNOW 3G integrity. `EIA2` (AES) is also supported. |
| `sgi_if_addr` | `172.16.0.1` | IP gateway for the LTE network |
| `db_file` | `/etc/srsran/user_db.csv` | Path to subscriber database |

### Subscriber Database (`configs/user_db.csv`)

Each line defines one subscriber (SIM card) the network will accept:

```csv
ue1,mil,001010123456789,00112233445566778899aabbccddeeff,opc,63bfa50ee6523365ff14c1f45f88737d,8000,000000001234,9,dynamic
```

| Field | Example | Description |
|-------|---------|-------------|
| Name | `ue1` | Human-readable label |
| Auth | `mil` | Authentication algorithm (`mil` = Milenage, `xor` = XOR) |
| IMSI | `001010123456789` | 15-digit subscriber identity. First 5 digits = MCC+MNC (`00101`). |
| Ki | `00112233...eeff` | 128-bit authentication key (32 hex chars) |
| OP_Type | `opc` | `opc` (pre-computed) or `op` (raw operator code) |
| OPc | `63bfa50e...737d` | 128-bit operator code (32 hex chars) |
| AMF | `8000` | Authentication Management Field |
| SQN | `000000001234` | Sequence number (12 hex chars). Increments with each auth. |
| QCI | `9` | QoS class (9 = default internet, 1 = voice, 5 = IMS signaling) |
| IP_alloc | `dynamic` | `dynamic` for DHCP-style, or a static IP like `172.16.0.2` |

**Important:** The Ki and OPc values here must exactly match what is programmed
onto the physical SIM card. If they don't match, authentication will fail and the
UE will not attach.

## Frequency Bands

### Verizon-Compatible Bands (USA)

| Band | dl_earfcn | Frequency | Bandwidth | Notes |
|------|-----------|-----------|-----------|-------|
| **13** | **5230** | **751 MHz** | **10 MHz** | **Current config.** Verizon primary band. All Verizon phones. |
| 2 | 900 | 1960 MHz | 20 MHz | PCS. Widely supported on all US carriers. |
| 4 | 2175 | 2132.5 MHz | 20 MHz | AWS. Widely supported. |
| 5 | 2525 | 881 MHz | 10 MHz | Cellular 850 MHz. Good building penetration. |
| 48 | 55990 | 3625 MHz | 10 MHz | CBRS. Legal for private LTE (GAA). Requires SAS & newer phones. |

### Other Bands

| Band | dl_earfcn | Frequency | Notes |
|------|-----------|-----------|-------|
| 3 | 1575 | 1842.5 MHz | Common in Europe/Asia. Not on US phones. |
| 7 | 3100 | 2655 MHz | Higher bandwidth, common in Europe. |

To change bands, edit `dl_earfcn` in `configs/enb.conf`. No other config changes
are needed.

## Programming SIM Cards with pySim

You need programmable SIM cards to use with this network. Retail carrier SIMs
(Verizon, AT&T, etc.) will **not** work because their authentication keys are
locked and unknown.

### What You Need

- **Programmable USIM cards** - Gialer Programmable SIM card
  [Gialer Programmable Sim](https://www.gialer.com/products/gialer-sim-card-program-kit-sim-card-tools-accessories-include-1-multi-sim-card-reader-5pcs-programmable-usim-cards-3-in-1-card-adapter-kit-newest-grsim-software-programer-tool?srsltid=AfmBOoo5l-ZU-6_c216B8v5sw5kdbMEBeHTe_KbDimyC7UbvSwjVal-k).
- **Smart card reader** - Any PC/SC-compatible USB reader. Common choices:
  - Omnikey 3121 (reliable, widely available)
  - ACS ACR38 / ACR39
  - Generic "USB Smart Card Reader" from Amazon (usually works)
- **pySim** - [PySim](https://github.com/osmocom/pysim) Open-source SIM programming tool 

### Installing pySim

```bash
# Install system dependencies
sudo apt install python3 python3-pip python3-venv \
    pcscd pcsc-tools libpcsclite-dev swig

# Start the smart card daemon
sudo systemctl enable --now pcscd

# Clone and install pySim
git clone https://gitea.osmocom.org/sim-card/pysim.git
cd pysim
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Verify your card reader is detected:

```bash
pcsc_scan
# Should show your reader and detect an inserted card
```

### Programming a SIM Card

Each SIM card must be programmed with values that match a row in `user_db.csv`.

#### Using pySim-prog (Simple)

```bash
cd pysim
source venv/bin/activate

./pySim-prog.py \
    -p 0 \
    -a <ADM_KEY> \
    --mcc 001 \
    --mnc 01 \
    --imsi 001010123456789 \
    -k 00112233445566778899aabbccddeeff \
    --opc 63bfa50ee6523365ff14c1f45f88737d \
    --acc 0001
```

| Flag | Description |
|------|-------------|
| `-p 0` | Card reader index (usually `0` for a single reader) |
| `-a <ADM_KEY>` | ADM key printed on your sysmocom SIM card carrier |
| `--mcc` / `--mnc` | Must match `enb.conf` and `epc.conf` |
| `--imsi` | Full 15-digit IMSI. First 5 digits must be MCC+MNC (`00101`). |
| `-k` | Ki (authentication key). Must match `user_db.csv`. |
| `--opc` | OPc value. Must match `user_db.csv`. |
| `--acc` | Access control class (`0001` allows normal access) |

#### Using pySim-shell (Interactive)

pySim-shell gives you more control and is better for inspecting or modifying
individual fields on an already-programmed card:

```bash
cd pysim
source venv/bin/activate

./pySim-shell.py -p 0

# Inside the pySim-shell REPL:

# Verify current card contents
pySIM-shell> select ADF.USIM
pySIM-shell> select EF.IMSI
pySIM-shell> read_binary_decoded

# Write IMSI
pySIM-shell> select MF
pySIM-shell> verify_adm <ADM_KEY>

pySIM-shell> select ADF.USIM
pySIM-shell> select EF.IMSI
pySIM-shell> update_binary_decoded '{"imsi": "001010123456789"}'

# Write PLMN selector (so the phone prefers your network)
pySIM-shell> select EF.PLMNsel
pySIM-shell> update_binary_decoded '[{"mcc": "001", "mnc": "01"}]'

# Write OPc
pySIM-shell> select ADF.USIM
pySIM-shell> select EF.OPc
pySIM-shell> update_binary_decoded '{"opc": "63bfa50ee6523365ff14c1f45f88737d"}'
```

### Programming Multiple Cards

For multiple subscribers, program each card with a unique IMSI (and optionally
unique Ki/OPc), and add a matching row in `user_db.csv`:

```bash
# Card 1
./pySim-prog.py -p 0 -a <ADM_KEY> \
    --mcc 001 --mnc 01 \
    --imsi 001010123456789 \
    -k 00112233445566778899aabbccddeeff \
    --opc 63bfa50ee6523365ff14c1f45f88737d \
    --acc 0001

# Card 2
./pySim-prog.py -p 0 -a <ADM_KEY> \
    --mcc 001 --mnc 01 \
    --imsi 001010123456790 \
    -k 00112233445566778899aabbccddeeff \
    --opc 63bfa50ee6523365ff14c1f45f88737d \
    --acc 0001
```

The corresponding `user_db.csv` entries:

```csv
ue1,mil,001010123456789,00112233445566778899aabbccddeeff,opc,63bfa50ee6523365ff14c1f45f88737d,8000,000000001234,9,dynamic
ue2,mil,001010123456790,00112233445566778899aabbccddeeff,opc,63bfa50ee6523365ff14c1f45f88737d,8000,000000001235,9,dynamic
```

> **Tip:** Using unique Ki/OPc per card is more secure. For lab testing, sharing
> keys across cards is fine and simplifies management.

### Connecting a Verizon Phone

1. **Unlock the phone** - The phone must accept non-Verizon SIMs. Verizon
   automatically unlocks phones after 60 days. You can check in
   Settings > About Phone > SIM Status.
2. **Insert the programmed SIM** - Replace the Verizon SIM with your
   programmable USIM.
3. **Set the APN** - Go to Settings > Network > Access Point Names and create
   a new APN:
   - Name: `Private LTE`
   - APN: `internet` (must match `apn` in `epc.conf`)
   - Leave all other fields at default
4. **Select the network** - Go to Settings > Network > Mobile Network >
   Network Operators > Search Networks. Select the test network (`001 01`
   or "Test Network").
5. **Verify attachment** - Check `/tmp/epc.log` on the server side for
   successful attach messages. The phone should get an IP in the `172.16.0.0/24`
   range.

## Troubleshooting

### PlutoSDR not detected

```bash
# Check network connectivity
ping 192.168.2.1

# Check USB connection
lsusb | grep Analog

# Check iio connectivity
iio_info -u ip:192.168.2.1
```

### Timing issues / underruns

- Reduce `n_prb` value (try 15 or 6)
- Ensure PlutoPlus has timestamp-enabled firmware
- Check for CPU throttling: `vcgencmd measure_temp`

### UE cannot attach

- Verify IMSI/Ki/OPc match between SIM and `user_db.csv`
- Check `dl_earfcn` matches your SIM's allowed bands
- Review logs: `/tmp/enb.log`, `/tmp/epc.log`

## Performance

Expected throughput with PlutoPlus SDR (25 PRB):

- Downlink: ~17 Mbps
- Uplink: ~9 Mbps

## File Structure

```
├── Dockerfile              # Multi-stage build for ARM64
├── docker-compose.yml      # Container orchestration
├── configs/
│   ├── enb.conf           # eNodeB configuration
│   ├── epc.conf           # EPC/Core configuration
│   ├── ue.conf            # UE configuration (for testing)
│   └── user_db.csv        # Subscriber database
└── scripts/
    ├── build-docker.sh    # Docker build helper
    ├── build-native.sh    # Native build script
    ├── entrypoint.sh      # Container entrypoint
    └── run.sh             # Run helper script

```

## License

This project assembles open-source components:
- srsRAN: AGPLv3
- SoapySDR: Boost Software License
- LibIIO: LGPLv2.1

## References
- [srsRAN Documentation](https://docs.srsran.com/)
- [srsRAN_4G](https://github.com/srsran/srsRAN_4G)
- [PlutoSDR Wiki](https://wiki.analog.com/university/tools/pluto)
- [pySim Source](https://gitea.osmocom.org/sim-card/pysim)
- [pySim User Manual](https://osmocom.org/projects/pysim/wiki)
- [sysmocom SIM Shop](https://shop.sysmocom.de/)

--
2026 - Gordon Young - gjyoung1974@gmail.com
