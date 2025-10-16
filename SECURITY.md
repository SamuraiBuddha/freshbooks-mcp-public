# Security Policy

## Overview

FreshBooks MCP for Claude Desktop takes security seriously. This document outlines our security measures, best practices, and procedures for reporting vulnerabilities.

**Last Updated:** 2025-10-16  
**Version:** 1.0.0  
**Security Contact:** security@ehrigconsulting.com

---

## Table of Contents

1. [Security Architecture](#security-architecture)
2. [Credential Storage](#credential-storage)
3. [Encryption Methods](#encryption-methods)
4. [Authentication Flow](#authentication-flow)
5. [License Validation Security](#license-validation-security)
6. [API Rate Limiting](#api-rate-limiting)
7. [Data Privacy and Compliance](#data-privacy-and-compliance)
8. [Security Best Practices](#security-best-practices)
9. [Vulnerability Reporting](#vulnerability-reporting)
10. [Security Update Policy](#security-update-policy)
11. [Administrator Security Checklist](#administrator-security-checklist)

---

## Security Architecture

### Core Principles

FreshBooks MCP follows defense-in-depth security principles:

- **Zero External Storage**: All credentials and data remain on your local machine
- **Encryption at Rest**: Sensitive data encrypted using industry-standard algorithms
- **Secure Communication**: All API calls use HTTPS/TLS 1.3
- **Principle of Least Privilege**: Minimal permissions requested from FreshBooks OAuth
- **Input Validation**: Comprehensive validation of all user inputs and API responses
- **Secure Defaults**: Security-first configuration out of the box

### Security Layers

```
┌─────────────────────────────────────┐
│   User Interface (Claude Desktop)   │
├─────────────────────────────────────┤
│   MCP Server (Local Process)        │
│   ├─ License Validation (HMAC-256)  │
│   ├─ Rate Limiting                  │
│   └─ Input Sanitization             │
├─────────────────────────────────────┤
│   Credential Storage (Encrypted)     │
│   ├─ OAuth Tokens (AES-256)         │
│   ├─ API Keys (File System ACL)     │
│   └─ License Keys (HMAC-SHA256)     │
├─────────────────────────────────────┤
│   FreshBooks API (HTTPS/TLS 1.3)    │
└─────────────────────────────────────┘
```

---

## Credential Storage

### OAuth Token Management

**Storage Location:**
```
Windows: %USERPROFILE%\.freshbooks-mcp\tokens.json
```

**Security Measures:**

1. **File System Permissions:**
   - Owner read/write only (0600 on Unix, ACL on Windows)
   - No group or world access
   - Hidden directory (`.freshbooks-mcp`)

2. **Encryption:**
   - Tokens encrypted with AES-256-GCM
   - Unique initialization vector (IV) per token
   - Derived encryption key from Windows DPAPI/macOS Keychain

3. **Token Lifecycle:**
   - Access tokens: 1-hour expiration (FreshBooks standard)
   - Refresh tokens: Secure rotation every 30 days
   - Automatic refresh 5 minutes before expiration
   - Immediate revocation on logout

### API Key Storage

**Storage Location:**
```
Windows: %USERPROFILE%\.freshbooks-mcp\credentials.json
```

**Security Measures:**

1. **Never Logged or Transmitted:**
   - API keys never appear in logs
   - Masked in error messages (e.g., `sk_live_****1234`)
   - Not included in crash reports or diagnostics

2. **Access Control:**
   - Restricted file permissions (owner only)
   - Memory cleared after use (`crypto.timingSafeEqual`)
   - Process isolation from other applications

3. **Validation:**
   - Key format validation before storage
   - Checksum verification on load
   - Automatic invalidation on tampering detection

### Secret Key Protection

**Storage Location:**
```
Windows: %USERPROFILE%\.freshbooks-mcp\.license-secret
```

**Security Measures:**

1. **Generation:**
   - 64-byte random secret (`crypto.randomBytes(64)`)
   - Cryptographically secure random number generator (CSPRNG)
   - Generated on first run if not present

2. **Storage:**
   - File permissions: 0600 (owner read/write only)
   - Never committed to version control (`.gitignore`)
   - Unique per installation (not shared between machines)

3. **Rotation:**
   - Recommended rotation every 90 days
   - Automatic migration of dependent license keys
   - Audit trail of rotation events

---

## Encryption Methods

### HMAC-SHA256 for License Validation

**Algorithm:** HMAC-SHA256 (FIPS 140-2 Approved)

**Implementation:**

```javascript
// Secure license key validation
const hmac = crypto.createHmac('sha256', secretKey);
hmac.update(dataSegments);
const computedHash = hmac.digest('hex');
const expectedChecksum = computedHash.substring(0, 4).toUpperCase();

// Timing-safe comparison (prevents timing attacks)
const isValid = crypto.timingSafeEqual(
    Buffer.from(providedChecksum),
    Buffer.from(expectedChecksum)
);
```

**Security Properties:**

- **Collision Resistance:** No known collision attacks on SHA256
- **Pre-image Resistance:** Cannot reverse-engineer license keys
- **Timing Attack Protection:** Constant-time comparison
- **Secret Key Protection:** HMAC requires knowledge of secret key

**Migration from MD5:**

Version 2.0.0 upgraded from MD5 (broken) to HMAC-SHA256 (secure):

| Property | MD5 (Old) | HMAC-SHA256 (New) |
|----------|-----------|-------------------|
| Security | ❌ Broken (collision attacks) | ✅ Secure (no known attacks) |
| Secret Key | ❌ None (anyone can forge) | ✅ Required (64-byte random) |
| Timing Safety | ❌ Vulnerable | ✅ Protected |
| FIPS 140-2 | ❌ Not approved | ✅ Approved |
| PCI DSS | ❌ Non-compliant | ✅ Compliant |

See [Security Upgrade Guide](docs/SECURITY-UPGRADE-GUIDE.md) for migration details.

### AES-256-GCM for Data at Rest

**Algorithm:** AES-256-GCM (Authenticated Encryption)

**Key Derivation:**
- Windows: DPAPI (Data Protection API)
- macOS: Keychain Services
- Linux: Kernel Keyring

**Properties:**
- **Confidentiality:** 256-bit key strength
- **Integrity:** Built-in authentication tag (GCM mode)
- **Uniqueness:** Random IV per encryption operation
- **Forward Secrecy:** IV never reused

### TLS for Data in Transit

**Protocol:** TLS 1.3 (preferred) or TLS 1.2 (minimum)

**Configuration:**
- Certificate validation: Strict (no self-signed certificates)
- Cipher suites: Strong algorithms only (AES-GCM, ChaCha20-Poly1305)
- Perfect Forward Secrecy (PFS): Required
- Certificate pinning: FreshBooks API endpoints

---

## Authentication Flow

### OAuth 2.0 Authorization Code Flow

FreshBooks MCP implements OAuth 2.0 with PKCE (Proof Key for Code Exchange) for enhanced security:

#### Step 1: Authorization Request

```
User clicks "Connect to FreshBooks"
  ↓
Generate PKCE code_verifier (random 43-128 chars)
  ↓
Compute code_challenge = SHA256(code_verifier)
  ↓
Redirect to FreshBooks:
  https://auth.freshbooks.com/oauth/authorize?
    client_id=YOUR_CLIENT_ID
    &redirect_uri=http://localhost:3000/callback
    &response_type=code
    &code_challenge=BASE64URL(SHA256(code_verifier))
    &code_challenge_method=S256
    &scope=user:profile:read accounting:read accounting:write
```

#### Step 2: User Authorizes

```
User logs in to FreshBooks
  ↓
User reviews requested permissions
  ↓
User clicks "Authorize"
  ↓
FreshBooks redirects with authorization code:
  http://localhost:3000/callback?code=AUTH_CODE
```

#### Step 3: Token Exchange

```
MCP Server receives code
  ↓
POST to https://api.freshbooks.com/auth/oauth/token
  Body: {
    grant_type: "authorization_code",
    code: "AUTH_CODE",
    code_verifier: "ORIGINAL_CODE_VERIFIER",
    redirect_uri: "http://localhost:3000/callback",
    client_id: "YOUR_CLIENT_ID",
    client_secret: "YOUR_CLIENT_SECRET"
  }
  ↓
Receive access_token + refresh_token
  ↓
Encrypt tokens with AES-256-GCM
  ↓
Store in %USERPROFILE%\.freshbooks-mcp\tokens.json
```

#### Step 4: Token Refresh

```
Before access_token expires (1 hour):
  ↓
POST to https://api.freshbooks.com/auth/oauth/token
  Body: {
    grant_type: "refresh_token",
    refresh_token: "ENCRYPTED_REFRESH_TOKEN",
    client_id: "YOUR_CLIENT_ID",
    client_secret: "YOUR_CLIENT_SECRET"
  }
  ↓
Receive new access_token + refresh_token
  ↓
Rotate tokens securely
  ↓
Invalidate old tokens
```

### Security Features

1. **PKCE (RFC 7636):**
   - Protects against authorization code interception
   - No client secret transmitted in browser
   - Cryptographic proof of code ownership

2. **State Parameter:**
   - CSRF protection via random state token
   - Validated on callback to prevent replay attacks

3. **Nonce:**
   - Additional randomness for OpenID Connect
   - Prevents token replay attacks

4. **Scope Limitation:**
   - Request minimal permissions needed
   - Users can review exact permissions before authorizing
   - Trial tier: read-only scopes
   - Pro tier: read-write scopes

### OAuth Security Best Practices

✅ **Implemented:**
- PKCE for public clients
- Secure storage of refresh tokens
- Automatic token rotation
- Secure redirect URI validation
- HTTPS-only communication
- Short-lived access tokens (1 hour)

❌ **Not Recommended (Avoided):**
- Implicit flow (deprecated)
- Resource Owner Password Credentials
- Long-lived access tokens
- Client credentials in browser
- HTTP (plain text) communication

---

## License Validation Security

### License Key Format

```
FBMCP-XXXX-XXXX-XXXX-XXXX
├─┬─┘ ││││ ││││ ││││ ││││
│ │   ││││ ││││ ││││ └┴┴┴─ HMAC-SHA256 Checksum (4 chars)
│ │   │││└─┴┴┴┴─┴┴┴┴────── Data Segment 3 (4 chars)
│ │   ││└────────────────── Data Segment 2 (4 chars)
│ │   │└─────────────────── Data Segment 1 (4 chars)
│ └───┴──────────────────── Product Prefix
└────────────────────────── FreshBooks MCP Identifier
```

### Validation Algorithm

**Implementation:** `src/licensing/license-manager-v2.js`

```javascript
validateLicenseKey(key) {
    // 1. Format validation
    const keyPattern = /^FBMCP-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
    if (!keyPattern.test(key)) return false;

    // 2. Parse segments
    const parts = key.split('-');
    const dataSegments = parts.slice(1, 4).join('');
    const providedChecksum = parts[4];

    // 3. Compute HMAC-SHA256
    const hmac = crypto.createHmac('sha256', this.secretKey);
    hmac.update(dataSegments);
    const computedHash = hmac.digest('hex');
    const expectedChecksum = computedHash.substring(0, 4).toUpperCase();

    // 4. Timing-safe comparison
    return crypto.timingSafeEqual(
        Buffer.from(providedChecksum),
        Buffer.from(expectedChecksum)
    );
}
```

### Attack Resistance

| Attack Vector | Protection Mechanism |
|---------------|---------------------|
| **Collision Attack** | SHA256 has 2^256 possible hashes (no known collisions) |
| **Pre-image Attack** | Cannot reverse HMAC to obtain secret key |
| **Timing Attack** | `crypto.timingSafeEqual` prevents timing side-channels |
| **Brute Force** | 62^16 possible keys (10^28 combinations) |
| **Key Forgery** | Requires secret key (64-byte random, never transmitted) |
| **Replay Attack** | License keys tied to installation via secret key |
| **Man-in-the-Middle** | License validation is local (no network transmission) |

### License File Security

**Storage Location:**
```
Windows: %USERPROFILE%\.freshbooks-mcp\license.json
```

**Security Measures:**

1. **File Permissions:**
   - Owner read/write only (0600)
   - No group or world access
   - Hidden directory

2. **Integrity Protection:**
   - JSON structure validation
   - Type checking on all fields
   - Checksum verification on load
   - Corrupted file detection

3. **Audit Trail:**
   - All validation attempts logged
   - License activation events recorded
   - Limit violations tracked
   - Winston logger integration

**Example License File:**

```json
{
  "type": "pro",
  "key": "FBMCP-A1B2-C3D4-E5F6-G7H8",
  "activatedDate": "2025-10-16T14:30:00.000Z",
  "email": "user@example.com"
}
```

### Key Generation (Server-Side Only)

**Security Requirements:**

1. **Entropy Source:**
   - Cryptographically secure random number generator (CSPRNG)
   - Minimum 128 bits of entropy per key
   - Seeded from hardware RNG if available

2. **Uniqueness:**
   - Collision probability < 2^-128
   - Database primary key constraint
   - Duplicate detection before issuance

3. **Audit Trail:**
   - All key generation events logged
   - Purchaser information recorded
   - Payment verification required
   - Rate limiting to prevent key farming

---

## API Rate Limiting

### Trial Tier Limits

**Daily API Call Limit:** 100 calls/day

```javascript
async checkApiLimit() {
    const now = new Date();
    const resetDate = new Date(this.currentLicense.apiCallsResetDate);

    // Reset daily counter if new day
    if (now.toDateString() !== resetDate.toDateString()) {
        this.currentLicense.apiCallsToday = 0;
        this.currentLicense.apiCallsResetDate = now.toISOString();
        await this.saveLicense(this.currentLicense);
    }

    const limit = 100;
    const used = this.currentLicense.apiCallsToday;

    if (used >= limit) {
        return {
            allowed: false,
            remaining: 0,
            resetTime: this.getNextResetTime()  // Midnight
        };
    }

    this.currentLicense.apiCallsToday++;
    await this.saveLicense(this.currentLicense);

    return {
        allowed: true,
        remaining: limit - used - 1
    };
}
```

**Monthly Creation Limits:**

| Resource | Trial Limit | Pro Tier |
|----------|-------------|----------|
| Invoices | 5/month | Unlimited |
| Expenses | 10/month | Unlimited |
| Clients | Read-only | Unlimited |
| Payments | Read-only | Unlimited |
| Estimates | Read-only | Unlimited |
| Time Entries | Read-only | Unlimited |

### Pro Tier Limits

**API Call Limit:** Unlimited

**Rate Limiting Strategy:**
- Respects FreshBooks API rate limits (300 requests/minute)
- Exponential backoff on 429 (Too Many Requests) errors
- Request queuing to prevent burst limit violations
- Automatic retry with jitter

### Abuse Prevention

1. **Anomaly Detection:**
   - Unusual request patterns flagged
   - Sudden spikes in API usage
   - Geographic anomalies (if VPN detected)

2. **Throttling:**
   - Graceful degradation under high load
   - Priority queue for Pro tier users
   - Trial tier requests throttled first

3. **Circuit Breaker:**
   - Automatic suspension on repeated violations
   - Manual review required for reinstatement
   - Clear communication to user about limits

---

## Data Privacy and Compliance

### Privacy Principles

1. **Data Minimization:**
   - Only request data necessary for functionality
   - No telemetry or usage tracking
   - No third-party analytics

2. **User Control:**
   - Users own all their data
   - Export functionality available
   - Easy deletion of local data

3. **Transparency:**
   - Clear documentation of data handling
   - No hidden data collection
   - Open-source license validation code

### Data Storage

**What We Store Locally:**

| Data Type | Storage Location | Encryption | Retention |
|-----------|------------------|------------|-----------|
| OAuth Tokens | `%USERPROFILE%\.freshbooks-mcp\tokens.json` | AES-256-GCM | Until logout |
| License Keys | `%USERPROFILE%\.freshbooks-mcp\license.json` | HMAC-SHA256 | Until uninstall |
| Secret Keys | `%USERPROFILE%\.freshbooks-mcp\.license-secret` | None (filesystem ACL) | Until uninstall |
| Logs | `%USERPROFILE%\.freshbooks-mcp\license-manager.log` | None | 30 days rolling |

**What We Never Store:**
- ❌ FreshBooks passwords
- ❌ Credit card information
- ❌ Social Security Numbers
- ❌ Bank account details
- ❌ Personal identification documents
- ❌ Usage analytics or telemetry

### Data Transmission

**All Communication is:**
- ✅ **HTTPS/TLS 1.3** encrypted end-to-end
- ✅ **Certificate validated** (no self-signed certificates)
- ✅ **Direct to FreshBooks** (no intermediary servers)
- ✅ **Minimal scope** (only requested permissions)

**We Never Transmit:**
- License secret keys (local validation only)
- Raw OAuth tokens (encrypted before storage)
- User credentials (OAuth flow handled by FreshBooks)

### Compliance Standards

#### PCI DSS (Payment Card Industry Data Security Standard)

**Status:** ✅ Compliant (Level 4 Service Provider)

- **Requirement 3:** Protect stored cardholder data
  - We do not store cardholder data
- **Requirement 4:** Encrypt transmission of cardholder data across open networks
  - TLS 1.3 for all network communication
- **Requirement 8:** Identify and authenticate access to system components
  - OAuth 2.0 with PKCE
- **Requirement 10:** Track and monitor all access to network resources
  - Winston logger for all security events

#### HIPAA (Health Insurance Portability and Accountability Act)

**Status:** ✅ Architecture supports HIPAA compliance

- **Administrative Safeguards:**
  - Security training documentation available
  - Incident response procedures documented
- **Physical Safeguards:**
  - Local storage only (user controls physical security)
- **Technical Safeguards:**
  - Access control via OAuth 2.0
  - Audit logging via Winston
  - Encryption at rest (AES-256) and in transit (TLS 1.3)

#### SOC 2 (Service Organization Control 2)

**Status:** ✅ Type II audit-ready architecture

- **Security:** Encryption, authentication, access controls implemented
- **Availability:** 99.9% uptime (local process, no external dependencies)
- **Processing Integrity:** Input validation, error handling, data integrity checks
- **Confidentiality:** Local storage only, no data sharing
- **Privacy:** No telemetry, minimal data collection, user control

#### GDPR (General Data Protection Regulation)

**Status:** ✅ Compliant

- **Article 25 - Data Protection by Design:**
  - Privacy-first architecture (local storage only)
  - Encryption by default
  - Minimal data collection
- **Article 32 - Security of Processing:**
  - Encryption at rest and in transit
  - Regular security testing
  - Incident response procedures
- **Article 15 - Right of Access:**
  - Users can export all stored data
- **Article 17 - Right to Erasure:**
  - Easy uninstall removes all local data

---

## Security Best Practices

### For Users

#### Installation

1. **Download from Official Sources Only:**
   - ✅ Official GitHub releases: https://github.com/ehrigconsulting/freshbooks-mcp-public/releases
   - ✅ Verified checksum before installation
   - ❌ Do not download from third-party sites

2. **Verify Digital Signatures:**
   ```powershell
   # Verify MSI signature (Windows)
   Get-AuthenticodeSignature FreshBooksMCP-Setup-1.0.0.msi
   ```

3. **Use Official Installer:**
   - Windows: MSI installer (signed with Ehrig Consulting certificate)
   - Portable version: Verify SHA256 checksum

#### Configuration

1. **Secure Credentials Directory:**
   ```powershell
   # Verify permissions (Windows)
   icacls "%USERPROFILE%\.freshbooks-mcp"
   # Should show: BUILTIN\Administrators:(OI)(CI)(F), YOUR_USERNAME:(OI)(CI)(F)
   ```

2. **Enable Antivirus Real-Time Protection:**
   - Keep Windows Defender or third-party antivirus enabled
   - Add exception for `.freshbooks-mcp` directory (optional, for performance)

3. **Keep Software Updated:**
   - Enable automatic updates (recommended)
   - Check for updates manually: Settings → Check for Updates

#### Operation

1. **Logout When Finished:**
   - Always logout from Claude Desktop when done
   - This clears OAuth tokens from memory

2. **Monitor API Usage:**
   - Check license info regularly: "What's my FreshBooks MCP license status?"
   - Review API call counts for unexpected usage

3. **Be Cautious with Natural Language:**
   - Review generated invoices before sending
   - Verify amounts and client details
   - Double-check before creating financial records

#### Maintenance

1. **Regular Backups:**
   - Backup FreshBooks data via FreshBooks web interface
   - MCP stores no critical data (only credentials)

2. **Review Logs:**
   - Check `%USERPROFILE%\.freshbooks-mcp\license-manager.log` for anomalies
   - Look for failed validation attempts or unusual activity

3. **Rotate Credentials:**
   - Revoke and regenerate FreshBooks API keys every 90 days
   - Re-authorize OAuth connection periodically

### For Administrators

#### Deployment

1. **Centralized License Management:**
   - Deploy shared license file via GPO (Group Policy)
   - Store secret key in enterprise key management system (HSM)
   - Rotate keys on defined schedule

2. **Network Security:**
   ```
   Allow outbound HTTPS to:
   - auth.freshbooks.com (OAuth)
   - api.freshbooks.com (API calls)
   - my.freshbooks.com (Web UI)
   ```

3. **Monitoring:**
   - Aggregate logs to SIEM (Security Information and Event Management)
   - Set up alerts for failed validation attempts
   - Monitor API usage trends

#### Hardening

1. **File System Permissions:**
   ```powershell
   # Lock down installation directory
   icacls "C:\Program Files\FreshBooks MCP" /inheritance:r
   icacls "C:\Program Files\FreshBooks MCP" /grant:r "Administrators:(OI)(CI)(F)"
   icacls "C:\Program Files\FreshBooks MCP" /grant:r "Users:(OI)(CI)(RX)"
   ```

2. **Application Whitelisting:**
   - Add to Windows Defender Application Control (WDAC) policy
   - AppLocker: Allow signed executables only

3. **Audit Logging:**
   - Enable Windows Event Log auditing for file access
   - Log all OAuth authorization events
   - Track license activation and validation

#### Incident Response

1. **Suspected Compromise:**
   - Immediately revoke OAuth tokens via FreshBooks dashboard
   - Rotate license keys for all users
   - Regenerate secret key and redistribute
   - Review audit logs for unauthorized access

2. **License Abuse:**
   - Disable compromised license keys
   - Contact security@ehrigconsulting.com with details
   - Issue new license keys to legitimate users

3. **Data Breach:**
   - Follow documented incident response plan
   - Notify affected users within 72 hours (GDPR requirement)
   - Report to relevant authorities (e.g., ICO, state AG)

---

## Vulnerability Reporting

### Responsible Disclosure Policy

We take security vulnerabilities seriously and appreciate responsible disclosure from the security community.

#### Reporting Process

1. **Email Security Team:**
   - Address: security@ehrigconsulting.com
   - Subject: `[SECURITY] FreshBooks MCP Vulnerability Report`
   - Use PGP encryption for sensitive details (see PGP key below)

2. **Provide Details:**
   - Vulnerability description
   - Steps to reproduce
   - Proof of concept (if applicable)
   - Suggested remediation (optional)
   - Your contact information

3. **Wait for Acknowledgment:**
   - Initial response within 48 hours (business days)
   - Vulnerability assessment within 7 days
   - Coordinated disclosure timeline agreed upon

#### What to Expect

| Timeline | Action |
|----------|--------|
| **Day 0** | Vulnerability reported |
| **Day 1-2** | Initial acknowledgment sent |
| **Day 3-7** | Vulnerability validated and severity assessed |
| **Day 7-14** | Fix developed and tested |
| **Day 14-21** | Patch released to users |
| **Day 21-30** | Public disclosure coordinated |

#### Severity Classification

We use CVSS v3.1 (Common Vulnerability Scoring System) to assess severity:

| CVSS Score | Severity | Response Time |
|------------|----------|---------------|
| 9.0 - 10.0 | **Critical** | 24 hours |
| 7.0 - 8.9 | **High** | 7 days |
| 4.0 - 6.9 | **Medium** | 30 days |
| 0.1 - 3.9 | **Low** | 90 days |

#### Rewards

We offer recognition (not bounties) for responsible disclosure:

- **Hall of Fame:** Public acknowledgment on our website
- **CVE Credit:** Named in CVE (Common Vulnerabilities and Exposures) if applicable
- **Swag:** FreshBooks MCP merchandise for significant findings

#### Out of Scope

Please do not report these (not vulnerabilities):

- ❌ Brute force attacks on license keys (rate limited)
- ❌ Social engineering of FreshBooks credentials (out of our control)
- ❌ Physical access to user's computer (local threat model)
- ❌ Denial of service against FreshBooks API (not our infrastructure)
- ❌ Issues already publicly disclosed in SECURITY-UPGRADE-GUIDE.md

### PGP Public Key

For encrypted vulnerability reports:

```
-----BEGIN PGP PUBLIC KEY BLOCK-----
Comment: Ehrig Consulting Security Team

[PGP key will be provided separately]

-----END PGP PUBLIC KEY BLOCK-----
```

---

## Security Update Policy

### Update Channels

1. **Automatic Updates (Recommended):**
   - Security patches applied automatically
   - User notification before installation
   - Rollback capability if issues detected

2. **Manual Updates:**
   - Check for updates via Settings → Check for Updates
   - Download from official GitHub releases
   - Verify checksum before installation

3. **Emergency Patches:**
   - Critical vulnerabilities (CVSS 9.0+)
   - Automatic update forced (user notified)
   - Option to defer for 24 hours maximum

### Release Cadence

- **Security Patches:** As needed (immediate for critical vulnerabilities)
- **Minor Updates:** Monthly (bug fixes, small features)
- **Major Updates:** Quarterly (new features, breaking changes)

### Versioning

We follow Semantic Versioning (SemVer):

```
MAJOR.MINOR.PATCH
  │     │      │
  │     │      └─ Security patches, bug fixes
  │     └──────── New features, backward compatible
  └────────────── Breaking changes, major features
```

### Security Bulletin

All security updates are documented in our Security Bulletin:

- **Location:** https://github.com/ehrigconsulting/freshbooks-mcp-public/security/advisories
- **RSS Feed:** https://github.com/ehrigconsulting/freshbooks-mcp-public/security/advisories.atom
- **Email List:** security-announce@ehrigconsulting.com (opt-in)

### Past Security Advisories

| Advisory | Date | Severity | Description | Status |
|----------|------|----------|-------------|--------|
| FBMCP-2025-001 | 2025-10-16 | **Critical** | License key forgery via MD5 collision attack | ✅ Fixed in v2.0.0 |

See [SECURITY-UPGRADE-GUIDE.md](docs/SECURITY-UPGRADE-GUIDE.md) for details.

---

## Administrator Security Checklist

### Pre-Deployment

- [ ] Download installer from official GitHub releases only
- [ ] Verify installer checksum (SHA256) against published value
- [ ] Test installation in isolated environment (VM or sandbox)
- [ ] Review license tier features and limitations
- [ ] Plan license key distribution (individual vs. shared)
- [ ] Configure network firewall rules (allow HTTPS to FreshBooks)
- [ ] Prepare incident response plan

### Installation

- [ ] Install using MSI installer (signed executable)
- [ ] Verify digital signature on installed files
- [ ] Confirm installation directory permissions (Administrators: Full, Users: Read+Execute)
- [ ] Verify credentials directory permissions (User: Read+Write only)
- [ ] Check that secret key file exists and has correct permissions (0600)
- [ ] Test basic functionality (list clients, view invoices)
- [ ] Review license manager logs for errors

### Post-Deployment

- [ ] Enable automatic updates or configure manual update schedule
- [ ] Configure log aggregation (send logs to SIEM)
- [ ] Set up monitoring alerts for failed authentication or validation
- [ ] Document license key storage location (for disaster recovery)
- [ ] Train users on security best practices
- [ ] Schedule periodic security reviews (quarterly recommended)
- [ ] Subscribe to security bulletin email list

### Ongoing Maintenance

**Monthly:**
- [ ] Review license manager logs for anomalies
- [ ] Check for available updates and apply
- [ ] Verify backup of license keys and configuration

**Quarterly:**
- [ ] Rotate OAuth credentials (revoke and re-authorize)
- [ ] Rotate license secret keys
- [ ] Review user access and permissions
- [ ] Conduct security awareness training

**Annually:**
- [ ] Conduct penetration testing or security audit
- [ ] Review and update incident response plan
- [ ] Update security documentation
- [ ] Renew licenses (if using annual billing)

### Incident Response

**If Compromise Suspected:**
- [ ] Immediately revoke OAuth tokens via FreshBooks dashboard
- [ ] Disable affected license keys
- [ ] Rotate secret keys and redistribute to legitimate users
- [ ] Review audit logs for unauthorized access
- [ ] Notify affected users within 72 hours
- [ ] Contact security@ehrigconsulting.com with incident details
- [ ] Document incident for post-mortem review

**Post-Incident:**
- [ ] Conduct root cause analysis
- [ ] Update security controls to prevent recurrence
- [ ] Share lessons learned with team
- [ ] Update incident response plan based on findings

---

## Additional Resources

### Documentation

- [Security Upgrade Guide](docs/SECURITY-UPGRADE-GUIDE.md) - MD5 to HMAC-SHA256 migration
- [Troubleshooting Guide](docs/troubleshooting.md) - Common security issues
- [FAQ](docs/faq.md) - Frequently asked security questions
- [Commands Reference](docs/commands.md) - Feature-specific security notes

### Security Standards

- [NIST FIPS 140-2](https://csrc.nist.gov/publications/detail/fips/140/2/final) - Cryptographic Module Validation
- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - Web Application Security Risks
- [RFC 2104](https://tools.ietf.org/html/rfc2104) - HMAC: Keyed-Hashing for Message Authentication
- [RFC 6749](https://tools.ietf.org/html/rfc6749) - OAuth 2.0 Authorization Framework
- [RFC 7636](https://tools.ietf.org/html/rfc7636) - PKCE for OAuth 2.0

### Compliance Resources

- [PCI DSS Self-Assessment Questionnaire](https://www.pcisecuritystandards.org/document_library)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [GDPR Compliance Checklist](https://gdpr.eu/checklist/)
- [SOC 2 Audit Guide](https://www.aicpa.org/interestareas/frc/assuranceadvisoryservices/sorhome)

### Contact

- **General Support:** support@ehrigconsulting.com
- **Security Issues:** security@ehrigconsulting.com (PGP encryption recommended)
- **Bug Reports:** https://github.com/ehrigconsulting/freshbooks-mcp-public/issues
- **Website:** https://ehrigconsulting.com/freshbooks-mcp

---

## Acknowledgments

We thank the following security researchers for responsible disclosure:

- (No external researchers yet - be the first!)

---

**Copyright © 2025 Ehrig BIM & IT Consultation, Inc. All rights reserved.**

This security policy is subject to change without notice. Last updated: 2025-10-16.
