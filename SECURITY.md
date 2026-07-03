# Security Findings - Screen Tally

**Review Date**: 2026-03-01
**Reviewer**: Alice (automated security review)
**Status**: Initial review

**Severity Summary**: 1 Critical, 2 High, 3 Medium, 1 Low

---

## Findings Table

| ID | Severity | Finding | File:Line | Status |
|----|----------|---------|-----------|--------|
| LL-01 | CRITICAL | Command injection in update trampoline script | UpdateManager.swift:222-249 | Open |
| LL-02 | HIGH | TCP listener binds on all interfaces (no localhost restriction) | TSLListener.swift:92 | Open |
| LL-03 | HIGH | No signature verification of downloaded updates | UpdateManager.swift | Open |
| LL-04 | MEDIUM | No authentication on TCP listener | TSLListener.swift:102-106 | Open |
| LL-05 | MEDIUM | Unbounded data buffer accumulation | TSLListener.swift:254 | Open |
| LL-06 | MEDIUM | Version string from GitHub API not validated before shell use | UpdateManager.swift:222-249 | Open |
| LL-07 | LOW | No rate limiting on TCP connections | TSLListener.swift:102 | Open |

---

## Detailed Findings

### LL-01: Command injection in update trampoline script (CRITICAL)

**File**: `UpdateManager.swift:222-249`

The `createTrampolineScript` method interpolates file paths directly into a bash script without escaping:

```swift
private func createTrampolineScript(pid: Int32, oldApp: URL, newApp: URL, tempDir: URL) -> String {
    """
    #!/bin/bash
    rm -rf "\(oldApp.path)"
    mv "\(newApp.path)" "\(oldApp.path)"
    codesign --force --deep --sign - "\(oldApp.path)"
    xattr -cr "\(oldApp.path)"
    open "\(oldApp.path)"
    rm -rf "\(tempDir.path)"
    """
}
```

This is the same vulnerable pattern as Whisper Verses (WV-01). If the app is installed at a path containing shell metacharacters, arbitrary commands could execute.

**Impact**: Arbitrary command execution during update process.
**Remediation**: POSIX-quote all interpolated paths (replace `'` with `'\''` and wrap in single quotes), or use `Process()` with argument arrays.

---

### LL-02: TCP listener binds on all interfaces (HIGH)

**File**: `TSLListener.swift:92`

The NWListener is created with default TCP parameters without setting `acceptLocalOnly = true`:

```swift
let newListener = try NWListener(using: .tcp, on: nwPort)
```

This binds on all network interfaces (0.0.0.0), making the TSL listener accessible from any device on the network. While this is functionally necessary (the Carbonite switcher connects over the network), it means any device on the LAN can connect.

**Impact**: Any device on the network can send TSL protocol data to the app, potentially displaying false tally states.
**Remediation**: This is likely intentional for the use case (Carbonite connects from the network). Document this as an accepted risk. Consider adding an IP allowlist for the expected Carbonite address.

---

### LL-03: No signature verification of downloaded updates (HIGH)

**File**: `UpdateManager.swift`

The self-update mechanism downloads a zip from GitHub Releases and applies it without cryptographic signature verification. The app also uses Sparkle (via AppDelegate), creating a dual update path.

**Impact**: Malicious update could replace the application if the download is intercepted.
**Remediation**: Remove the custom update mechanism and rely solely on Sparkle, which provides EdDSA signature verification. If the custom updater is needed, add signature verification.

---

### LL-04: No authentication on TCP listener (MEDIUM)

**File**: `TSLListener.swift:102-106`

The TCP listener accepts any incoming connection without authentication:

```swift
newListener.newConnectionHandler = { [weak self] conn in
    Task { @MainActor in
        self?.handleIncomingConnection(conn)
    }
}
```

Any client that connects and sends valid TSL protocol data will be accepted.

**Impact**: Unauthorized devices can send tally commands, causing false visual indicators.
**Remediation**: The TSL protocol does not define authentication. Document as accepted risk. Consider logging the source IP of connections for audit purposes.

---

### LL-05: Unbounded data buffer accumulation (MEDIUM)

**File**: `TSLListener.swift:254`

The receive buffer accumulates data without a size limit:

```swift
self.dataBuffer.append(data)
```

While the protocol parser drains the buffer, a malicious client sending data faster than it can be parsed could cause memory growth. The buffer IS cleared when the protocol parser encounters unrecognizable framing (line 298: `dataBuffer.removeAll()`), which provides some protection.

**Impact**: Potential memory exhaustion from a malicious client sending data faster than parsing.
**Remediation**: Add a maximum buffer size (e.g., 64KB). The largest valid TSL 5.0 message is 1002 bytes (PBC max 1000 + 2), so 64KB provides ample headroom.

---

### LL-06: Version string from GitHub API not validated (MEDIUM)

**File**: `UpdateManager.swift:222-249`

The version tag from the GitHub API is used in the trampoline script path construction and logged, but is not validated with a regex before being embedded in the shell script. Compare with Mirage's `RcloneInstaller.swift:91` which correctly validates `^v\d+\.\d+\.\d+$`.

**Impact**: Crafted version string from compromised GitHub API could contribute to command injection.
**Remediation**: Validate the version string format with regex `^v\d+\.\d+\.\d+$` before use.

---

### LL-07: No rate limiting on TCP connections (LOW)

**File**: `TSLListener.swift:102`

New connections are accepted without rate limiting. The listener does replace the previous connection with each new one (line 175-178), which limits the impact, but rapid connection cycling could cause resource churn.

**Impact**: Minor resource churn from rapid connection cycling.
**Remediation**: Add a minimum interval between accepting new connections, or ignore new connections within a cooldown period after the last connection.

---

## Security Posture Assessment

Screen Tally has a moderate attack surface due to its TCP network listener and self-update mechanism. The TCP listener intentionally accepts connections from the LAN (required for Carbonite integration), which is appropriate for its use case but should be documented. The most critical issue is the shared update trampoline vulnerability (LL-01), identical to Whisper Verses. The app also has Sparkle integration, creating a redundant (and potentially conflicting) update path.

**Overall Risk**: MEDIUM-HIGH - The critical finding is in the update mechanism. The network listener is intentionally exposed but lacks basic protections.

---

## Remediation Priority

1. **LL-01** (CRITICAL) - Fix path quoting in trampoline script
2. **LL-03** (HIGH) - Add signature verification or consolidate on Sparkle
3. **LL-02** (HIGH) - Document network binding as accepted risk, consider IP allowlist
4. **LL-05** (MEDIUM) - Add buffer size limit
5. **LL-06** (MEDIUM) - Add version string validation
6. **LL-04** (MEDIUM) - Document lack of TSL auth as accepted risk
7. **LL-07** (LOW) - Consider connection rate limiting
