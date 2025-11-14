# Application Integration & Testing Features

**Category:** Application Integration
**Phase:** 5
**Priority:** P0 (Critical Path)
**Dependencies:** Features 1-11 (System Complete)

## Overview

These features integrate the user platform application into the firmware image and create comprehensive hardware testing procedures.

---

## Feature 12: User Platform Application Integration

**Status:** ⏸️ Planning
**Estimated Effort:** 5-7 days
**Owner:** TBD

### Description

Integrate the user platform application into the rootfs and configure automatic startup via systemd.

### User Stories

#### Story 12.1: Integrate application into rootfs

**Tasks:**
- [ ] Create application installation directory structure
- [ ] Package application binaries and dependencies
- [ ] Create application configuration files
- [ ] Set up application data directories
- [ ] Configure file permissions and ownership
- [ ] Install application into rootfs during image build
- [ ] Create application update mechanism
- [ ] Document application integration in `docs/app-integration.md`

**Acceptance Criteria:**
- Application installed in correct location (`/opt/platform-app/`)
- All dependencies included
- Configuration files present
- Correct permissions set
- Application can be updated independently
- Integration documented

---

#### Story 12.2: Configure and test application startup

**Tasks:**
- [ ] Create systemd service file for application
- [ ] Configure service dependencies
- [ ] Set up pre-start checks
- [ ] Configure restart policy
- [ ] Set resource limits (if needed)
- [ ] Enable service in systemd
- [ ] Test manual start/stop
- [ ] Test automatic startup on boot
- [ ] Configure logging
- [ ] Test application functionality
- [ ] Measure startup time

**Acceptance Criteria:**
- Systemd service created and configured
- Application starts automatically on boot
- Service starts reliably
- Application launches and runs correctly
- Logs captured correctly
- Restart policy works
- Startup time acceptable

### Dependencies

**Upstream:**
- Feature 7: Rootfs Construction (base filesystem)
- Feature 8: Image Assembly (integration point)

**Downstream:**
- Feature 11: Partial Update Engine (application updates)
- Feature 13: Hardware Interface Test Suite (tests application hardware access)

### Validation Checklist

- [ ] Application binaries installed
- [ ] Dependencies satisfied
- [ ] Configuration files present
- [ ] Data directories created
- [ ] Permissions correct
- [ ] Systemd service configured
- [ ] Service enabled
- [ ] Auto-start works
- [ ] Application functions correctly
- [ ] Logs accessible
- [ ] Application can be updated

### Artifacts

- `docs/app-integration.md` - Integration documentation
- `config/platform-app.service` - Systemd service file
- `scripts/install-application.sh` - Application installer
- `scripts/app-startup-test.sh` - Startup validation script

---

## Feature 13: Hardware Interface Test Suite

**Status:** ⏸️ Planning
**Estimated Effort:** 10-15 days
**Owner:** TBD

### Description

Create comprehensive automated test suite covering all platform-specific hardware peripherals.

### User Stories

#### Story 13.1: Create test suite for all platform devices

**Tasks:**
- [ ] Design test framework structure
- [ ] Implement tests for each peripheral:
  - [ ] **Card Reader** - Read card data, verify communication
  - [ ] **Barcode Scanner** - Scan test barcodes, validate output
  - [ ] **Touchscreen Display** - Test touch input, display output
  - [ ] **Receipt Printer** - Print test pattern, verify operation
  - [ ] **Cash Acceptor** - Test bill acceptance (if installed)
  - [ ] **Ethernet** - Link test, throughput test
  - [ ] **Wi-Fi** - Scan networks, connection test
  - [ ] **USB Hub** - Enumerate devices, bandwidth test
  - [ ] **Storage (eMMC)** - Read/write speed test
  - [ ] **Storage (SD)** - Read/write speed test
  - [ ] **Audio Output** - Play test tone, verify output
  - [ ] **GPIO Buttons** - Test button inputs
  - [ ] **Door Sensor** - Test open/close detection
  - [ ] **Status LEDs** - Test LED control
  - [ ] **RTC** - Read/write time
  - [ ] **Watchdog** - Test watchdog functionality
- [ ] Implement test result logging
- [ ] Create test report generator
- [ ] Add interactive test mode (for manual peripherals)
- [ ] Add automated test mode
- [ ] Document test suite in `docs/hardware-test-suite.md`

**Acceptance Criteria:**
- Test for each peripheral implemented
- Tests can run individually or as suite
- Pass/Fail result reported for each test
- Test logs created
- Interactive mode for manual tests
- Automated mode for scripted tests
- Test suite documented

---

#### Story 13.2: Run test suite and document results

**Tasks:**
- [ ] Execute complete test suite on hardware
- [ ] Document PASS/FAIL for each peripheral
- [ ] Investigate and document any failures
- [ ] Create baseline test results
- [ ] Create test execution guide
- [ ] Add test suite to CI/CD (where applicable)
- [ ] Create test report template

**Acceptance Criteria:**
- Tests executed on platform hardware
- PASS/FAIL documented for each peripheral
- Baseline results established
- Known issues documented
- Test execution guide created
- Report template available

### Test Implementation Examples

**Card Reader Test:**
```bash
#!/bin/bash
# Test card reader communication
echo "Testing card reader..."
if lsusb | grep -q "Card Reader"; then
    echo "Card reader detected: PASS"
    # Additional functional tests
else
    echo "Card reader NOT detected: FAIL"
    exit 1
fi
```

**Network Test:**
```bash
#!/bin/bash
# Test Ethernet connectivity
echo "Testing Ethernet..."
if ip link show eth0 | grep -q "state UP"; then
    if ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
        echo "Ethernet functional: PASS"
    else
        echo "Ethernet link up but no connectivity: WARN"
    fi
else
    echo "Ethernet link down: FAIL"
    exit 1
fi
```

**Storage Performance Test:**
```bash
#!/bin/bash
# Test eMMC performance
echo "Testing eMMC performance..."
TEST_FILE="/tmp/test_data"
dd if=/dev/zero of=$TEST_FILE bs=1M count=100 conv=fsync 2>&1 | \
    grep -oP '\\d+(\\.\\d+)? MB/s' | \
    awk '{print "Write speed: " $0}'
# Expected: > 50 MB/s for eMMC
```

### Artifacts

- `docs/hardware-test-suite.md` - Test suite documentation
- `tests/hardware-suite/` - Test scripts directory
- `tests/run-all-tests.sh` - Master test runner
- `tests/test-results-template.md` - Results template
- `logs/baseline-test-results.log` - Baseline results
- `reports/hardware-validation-report.pdf` - Test report

---

## Feature 14: Board Bring-Up Test Procedures

**Status:** ⏸️ Planning
**Estimated Effort:** 5-7 days
**Owner:** TBD

### Description

Create standardized bring-up checklist and procedures for validating new hardware units in production or development.

### User Stories

#### Story 14.1: Create platform bring-up checklist

**Tasks:**
- [ ] Define bring-up procedure phases:
  - [ ] Phase 1: Power and boot validation
  - [ ] Phase 2: Core hardware validation
  - [ ] Phase 3: Peripheral validation
  - [ ] Phase 4: Application validation
- [ ] Create detailed checklist items for each peripheral:
  - [ ] Card reader communication
  - [ ] Barcode scanner functionality
  - [ ] Display output and touch input
  - [ ] Printer operation
  - [ ] Cash acceptor (if present)
  - [ ] Ethernet connectivity
  - [ ] Wi-Fi functionality
  - [ ] USB device enumeration
  - [ ] Storage read/write
  - [ ] Audio output
  - [ ] GPIO button inputs
  - [ ] Door sensor operation
  - [ ] LED indicators
- [ ] Create bring-up test script
- [ ] Create bring-up report template
- [ ] Define acceptance criteria for each test
- [ ] Document bring-up procedure in `docs/board-bring-up.md`
- [ ] Get engineering lead review and approval

**Acceptance Criteria:**
- Bring-up checklist created
- All platform peripherals covered
- Explicit PASS/FAIL criteria defined
- Bring-up script implemented
- Report template created
- Procedure reviewed and approved by engineering lead

---

#### Story 14.2: Execute bring-up procedure and record findings

**Tasks:**
- [ ] Execute bring-up on new platform unit
- [ ] Follow checklist systematically
- [ ] Record PASS/FAIL for each item
- [ ] Document any issues encountered
- [ ] Capture evidence (logs, photos)
- [ ] Complete bring-up report
- [ ] Identify items needing engineering follow-up
- [ ] Create issues for failures
- [ ] Archive bring-up results

**Acceptance Criteria:**
- Bring-up completed successfully on platform unit
- PASS/FAIL recorded for each checklist item
- Issues documented for engineering follow-up
- Evidence captured
- Bring-up report completed and archived
- Process validated and confirmed repeatable

### Bring-Up Checklist Example

```markdown
## Platform Unit Bring-Up Checklist

**Unit Serial:** ___________
**Date:** ___________
**Technician:** ___________

### Phase 1: Power & Boot
- [ ] PASS / FAIL - Power supply voltage correct (12V ±5%)
- [ ] PASS / FAIL - Current draw within spec (< 2A idle)
- [ ] PASS / FAIL - U-Boot loads and displays on serial console
- [ ] PASS / FAIL - Kernel boots to login prompt
- [ ] PASS / FAIL - Boot time < 30 seconds

### Phase 2: Core Hardware
- [ ] PASS / FAIL - eMMC detected and accessible
- [ ] PASS / FAIL - RAM size correct (check /proc/meminfo)
- [ ] PASS / FAIL - CPU frequency correct (check cpufreq)
- [ ] PASS / FAIL - Temperature sensors readable

### Phase 3: Peripherals
- [ ] PASS / FAIL - Card reader: Device detected via USB
- [ ] PASS / FAIL - Card reader: Successfully read test card
- [ ] PASS / FAIL - Barcode scanner: Device detected
- [ ] PASS / FAIL - Barcode scanner: Scan test barcode
- [ ] PASS / FAIL - Display: Image visible on screen
- [ ] PASS / FAIL - Touchscreen: Touch events detected
- [ ] PASS / FAIL - Printer: Device detected
- [ ] PASS / FAIL - Printer: Print test receipt
- [ ] PASS / FAIL - Cash acceptor: Device detected (if installed)
- [ ] PASS / FAIL - Ethernet: Link up, DHCP address obtained
- [ ] PASS / FAIL - Wi-Fi: Networks detected
- [ ] PASS / FAIL - USB hub: All ports functional
- [ ] PASS / FAIL - Audio: Test tone audible
- [ ] PASS / FAIL - GPIO buttons: All buttons responsive
- [ ] PASS / FAIL - Door sensor: Open/close detection works
- [ ] PASS / FAIL - Status LEDs: All LEDs controllable

### Phase 4: Application
- [ ] PASS / FAIL - Application starts automatically
- [ ] PASS / FAIL - Application UI loads
- [ ] PASS / FAIL - Application responsive to input

### Issues Identified
| Issue # | Description | Severity | Status |
|---------|-------------|----------|--------|
|         |             |          |        |

### Sign-Off
**Technician:** ___________ **Date:** ___________
**Engineer:** ___________ **Date:** ___________
```

### Dependencies

**Upstream:**
- Feature 5: Device Tree & Hardware Enablement (drivers functional)
- Feature 13: Hardware Interface Test Suite (test implementation)

**Downstream:**
- Production manufacturing (uses bring-up procedure)
- Field service (uses for troubleshooting)

### Artifacts

- `docs/board-bring-up.md` - Bring-up procedure documentation
- `docs/bring-up-checklist.md` - Checklist template
- `scripts/bring-up-test.sh` - Automated bring-up script
- `templates/bring-up-report.md` - Report template
- `reports/bring-up-results/` - Archived results

---

## Phase Completion Criteria

Application Integration & Testing phase is complete when:

- ✅ User platform application integrated
- ✅ Application auto-starts correctly
- ✅ Hardware test suite implemented
- ✅ All peripheral tests functional
- ✅ Test suite executed and baseline established
- ✅ Bring-up procedure created and approved
- ✅ Bring-up executed successfully on hardware
- ✅ All documentation complete
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [Build Infrastructure](./07-build-infrastructure.md) (Features 15-17)
2. Establish reproducible builds
3. Implement CI/CD pipeline
4. Automate artifact packaging
