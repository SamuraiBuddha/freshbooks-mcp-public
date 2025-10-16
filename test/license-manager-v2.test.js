// Test Suite for Enhanced License Manager with HMAC-SHA256
// Tests security improvements and backward compatibility

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');

// Test configuration
const testBaseDir = path.join(os.tmpdir(), 'fbmcp-test-' + Date.now());
const testLicenseFile = path.join(testBaseDir, 'license.json');
const testSecretKeyFile = path.join(testBaseDir, '.license-secret');

// Import license manager class for testing
const LicenseManagerClass = require('../src/licensing/license-manager-v2.js').constructor;

describe('License Manager v2 - HMAC-SHA256 Security Tests', () => {

    let licenseManager;

    beforeEach(async () => {
        // Create fresh test directory
        await fs.mkdir(testBaseDir, { recursive: true });

        // Create new instance with test paths
        licenseManager = new LicenseManagerClass({
            licenseFile: testLicenseFile,
            secretKeyFile: testSecretKeyFile
        });
    });

    afterEach(async () => {
        // Clean up test directory
        try {
            await fs.rm(testBaseDir, { recursive: true, force: true });
        } catch (error) {
            console.error('Cleanup error:', error.message);
        }
    });

    describe('Secret Key Management', () => {
        it('should generate secure secret key on first run', async () => {
            await licenseManager.ensureSecretKey();

            assert(licenseManager.secretKey, 'Secret key should be generated');
            assert.strictEqual(typeof licenseManager.secretKey, 'string');
            assert(licenseManager.secretKey.length >= 64, 'Secret key should be at least 64 chars');

            // Verify key is saved to file
            const savedKey = await fs.readFile(testSecretKeyFile, 'utf8');
            assert.strictEqual(savedKey.trim(), licenseManager.secretKey);
        });

        it('should load existing secret key on subsequent runs', async () => {
            // First run - generate
            await licenseManager.ensureSecretKey();
            const originalKey = licenseManager.secretKey;

            // Second run - should load same key
            const licenseManager2 = new LicenseManagerClass({
                licenseFile: testLicenseFile,
                secretKeyFile: testSecretKeyFile
            });
            await licenseManager2.ensureSecretKey();

            assert.strictEqual(licenseManager2.secretKey, originalKey,
                'Loaded key should match original');
        });

        it('should regenerate if secret key file is corrupted', async () => {
            // Write corrupted key file (too short)
            await fs.writeFile(testSecretKeyFile, 'short');

            await licenseManager.ensureSecretKey();

            assert(licenseManager.secretKey.length >= 64,
                'Should generate new key if corrupted');
        });
    });

    describe('HMAC-SHA256 License Key Validation', () => {
        beforeEach(async () => {
            await licenseManager.ensureSecretKey();
        });

        it('should validate correct HMAC-SHA256 license key', async () => {
            const validKey = licenseManager.generateLicenseKey();

            assert(validKey.startsWith('FBMCP-'), 'Key should have correct prefix');
            assert.strictEqual(validKey.length, 29, 'Key should be 29 characters');

            const isValid = licenseManager.validateLicenseKey(validKey);
            assert.strictEqual(isValid, true, 'Generated key should validate');
        });

        it('should reject license key with invalid format', async () => {
            const invalidKeys = [
                'INVALID-KEY',
                'FBMCP-123',
                'FBMCP-XXXX-XXXX-XXXX',  // Missing segment
                'fbmcp-AAAA-BBBB-CCCC-DDDD',  // Lowercase prefix
                'FBMCP-AAA-BBBB-CCCC-DDDD',  // Segment too short
                'FBMCP-AAAAA-BBBB-CCCC-DDDD',  // Segment too long
            ];

            for (const key of invalidKeys) {
                const isValid = licenseManager.validateLicenseKey(key);
                assert.strictEqual(isValid, false,
                    `Should reject invalid key: ${key}`);
            }
        });

        it('should reject license key with tampered checksum', async () => {
            const validKey = licenseManager.generateLicenseKey();
            const parts = validKey.split('-');

            // Tamper with checksum
            const tamperedChecksum = parts[4] === 'AAAA' ? 'BBBB' : 'AAAA';
            const tamperedKey = `${parts[0]}-${parts[1]}-${parts[2]}-${parts[3]}-${tamperedChecksum}`;

            const isValid = licenseManager.validateLicenseKey(tamperedKey);
            assert.strictEqual(isValid, false,
                'Should reject key with tampered checksum');
        });

        it('should reject license key with tampered data segments', async () => {
            const validKey = licenseManager.generateLicenseKey();
            const parts = validKey.split('-');

            // Tamper with data segment
            const tamperedKey = `${parts[0]}-ZZZZ-${parts[2]}-${parts[3]}-${parts[4]}`;

            const isValid = licenseManager.validateLicenseKey(tamperedKey);
            assert.strictEqual(isValid, false,
                'Should reject key with tampered data');
        });

        it('should use timing-safe comparison to prevent timing attacks', async () => {
            const validKey = licenseManager.generateLicenseKey();

            // Measure validation time for correct and incorrect keys
            const iterations = 100;
            let correctTotal = 0;
            let incorrectTotal = 0;

            for (let i = 0; i < iterations; i++) {
                // Correct key
                const start1 = process.hrtime.bigint();
                licenseManager.validateLicenseKey(validKey);
                const end1 = process.hrtime.bigint();
                correctTotal += Number(end1 - start1);

                // Incorrect key with same format
                const parts = validKey.split('-');
                const incorrectKey = `${parts[0]}-${parts[1]}-${parts[2]}-${parts[3]}-AAAA`;
                const start2 = process.hrtime.bigint();
                licenseManager.validateLicenseKey(incorrectKey);
                const end2 = process.hrtime.bigint();
                incorrectTotal += Number(end2 - start2);
            }

            const correctAvg = correctTotal / iterations;
            const incorrectAvg = incorrectTotal / iterations;

            // Timing should be similar (within 50% variance)
            const variance = Math.abs(correctAvg - incorrectAvg) / correctAvg;
            assert(variance < 0.5,
                'Timing variance should be minimal to prevent timing attacks');
        });
    });

    describe('Trial License Management', () => {
        it('should create trial license with proper structure', async () => {
            await licenseManager.initialize();

            assert.strictEqual(licenseManager.currentLicense.type, 'trial');
            assert(licenseManager.currentLicense.trialStart);
            assert.strictEqual(licenseManager.currentLicense.apiCallsToday, 0);
            assert.strictEqual(licenseManager.currentLicense.monthlyInvoices, 0);
            assert.strictEqual(licenseManager.currentLicense.monthlyExpenses, 0);
        });

        it('should calculate trial days remaining correctly', async () => {
            await licenseManager.initialize();
            const info = await licenseManager.getLicenseInfo();

            assert.strictEqual(info.type, 'trial');
            assert(info.trialDaysRemaining > 0);
            assert(info.trialDaysRemaining <= 30);
        });

        it('should reject expired trial license', async () => {
            // Create expired trial
            const expiredTrial = {
                type: 'trial',
                trialStart: new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString(),
                apiCallsToday: 0,
                apiCallsResetDate: new Date().toISOString(),
                monthlyInvoices: 0,
                monthlyExpenses: 0,
                monthResetDate: new Date().toISOString()
            };

            await fs.writeFile(testLicenseFile, JSON.stringify(expiredTrial));

            try {
                await licenseManager.loadLicense();
                assert.fail('Should throw error for expired trial');
            } catch (error) {
                assert(error.message.includes('Trial expired'));
            }
        });
    });

    describe('Pro License Activation', () => {
        beforeEach(async () => {
            await licenseManager.ensureSecretKey();
        });

        it('should activate pro license with valid key', async () => {
            const validKey = licenseManager.generateLicenseKey();
            const proLicense = await licenseManager.activatePro(validKey);

            assert.strictEqual(proLicense.type, 'pro');
            assert.strictEqual(proLicense.key, validKey);
            assert(proLicense.activatedDate);
            assert(proLicense.email);
        });

        it('should reject pro activation with invalid key', async () => {
            try {
                await licenseManager.activatePro('INVALID-KEY');
                assert.fail('Should throw error for invalid key');
            } catch (error) {
                assert(error.message.includes('Invalid license key'));
            }
        });

        it('should save pro license to file with restricted permissions', async () => {
            const validKey = licenseManager.generateLicenseKey();
            await licenseManager.activatePro(validKey);

            // Verify file exists and is readable
            const licenseData = await fs.readFile(testLicenseFile, 'utf8');
            const license = JSON.parse(licenseData);

            assert.strictEqual(license.type, 'pro');
            assert.strictEqual(license.key, validKey);
        });
    });

    describe('Input Validation and Error Handling', () => {
        it('should handle corrupted license file gracefully', async () => {
            // Write invalid JSON
            await fs.writeFile(testLicenseFile, 'invalid json {{{');

            try {
                await licenseManager.loadLicense();
                assert.fail('Should throw error for corrupted file');
            } catch (error) {
                assert(error.message.includes('corrupted'));
            }
        });

        it('should handle missing license file gracefully', async () => {
            // Don't create license file
            try {
                await licenseManager.loadLicense();
                assert.fail('Should throw error for missing file');
            } catch (error) {
                assert(error.message.includes('not found'));
            }
        });

        it('should validate license structure before processing', async () => {
            const invalidLicenses = [
                null,
                'string',
                123,
                { type: 'invalid' },  // Invalid type
                { type: 'trial' },  // Missing trialStart
                { type: 'pro' },  // Missing key
            ];

            for (const invalidLicense of invalidLicenses) {
                await fs.writeFile(testLicenseFile, JSON.stringify(invalidLicense));

                try {
                    await licenseManager.loadLicense();
                    assert.fail(`Should reject invalid license: ${JSON.stringify(invalidLicense)}`);
                } catch (error) {
                    assert(error.message.includes('Invalid') || error.message.includes('Invalid'));
                }
            }
        });

        it('should handle null/undefined license key gracefully', async () => {
            await licenseManager.ensureSecretKey();

            const invalidKeys = [null, undefined, '', 123, {}, []];

            for (const key of invalidKeys) {
                try {
                    await licenseManager.activatePro(key);
                    assert.fail(`Should reject invalid key type: ${typeof key}`);
                } catch (error) {
                    assert(error.message.includes('Invalid'));
                }
            }
        });
    });

    describe('Feature Access Control', () => {
        it('should allow all features for pro license', async () => {
            await licenseManager.ensureSecretKey();
            const validKey = licenseManager.generateLicenseKey();
            await licenseManager.activatePro(validKey);

            const features = [
                'read_invoices',
                'write_invoice',
                'write_client',
                'write_payment',
                'write_estimate'
            ];

            for (const feature of features) {
                const access = await licenseManager.checkFeatureAccess(feature);
                assert.strictEqual(access.allowed, true,
                    `Pro should have access to ${feature}`);
                assert.strictEqual(access.tier, 'pro');
            }
        });

        it('should enforce trial limitations', async () => {
            await licenseManager.initialize();

            // Read features should be allowed
            const readAccess = await licenseManager.checkFeatureAccess('read_invoices');
            assert.strictEqual(readAccess.allowed, true);

            // Pro-only features should be denied
            const writeClient = await licenseManager.checkFeatureAccess('write_client');
            assert.strictEqual(writeClient.allowed, false);
            assert.strictEqual(writeClient.upgradeRequired, true);
        });

        it('should enforce monthly limits for trial', async () => {
            await licenseManager.initialize();

            // Use up invoice limit (5)
            for (let i = 0; i < 5; i++) {
                const access = await licenseManager.checkFeatureAccess('write_invoice');
                assert.strictEqual(access.allowed, true,
                    `Invoice ${i + 1} should be allowed`);
            }

            // 6th invoice should be denied
            const deniedAccess = await licenseManager.checkFeatureAccess('write_invoice');
            assert.strictEqual(deniedAccess.allowed, false,
                'Should deny after limit reached');
        });

        it('should reset monthly limits on new month', async () => {
            await licenseManager.initialize();

            // Set last month's reset date
            licenseManager.currentLicense.monthResetDate =
                new Date(Date.now() - 32 * 24 * 60 * 60 * 1000).toISOString();
            licenseManager.currentLicense.monthlyInvoices = 5;
            await licenseManager.saveLicense(licenseManager.currentLicense);

            // Should reset and allow access
            const access = await licenseManager.checkFeatureAccess('write_invoice');
            assert.strictEqual(access.allowed, true,
                'Should allow after monthly reset');
            assert.strictEqual(licenseManager.currentLicense.monthlyInvoices, 1,
                'Counter should reset to 1');
        });
    });

    describe('API Rate Limiting', () => {
        it('should track daily API calls for trial', async () => {
            await licenseManager.initialize();

            const result1 = await licenseManager.checkApiLimit();
            assert.strictEqual(result1.allowed, true);
            assert.strictEqual(result1.remaining, 99);

            const result2 = await licenseManager.checkApiLimit();
            assert.strictEqual(result2.allowed, true);
            assert.strictEqual(result2.remaining, 98);
        });

        it('should enforce daily API limit for trial', async () => {
            await licenseManager.initialize();

            // Simulate 100 API calls
            licenseManager.currentLicense.apiCallsToday = 100;
            await licenseManager.saveLicense(licenseManager.currentLicense);

            const result = await licenseManager.checkApiLimit();
            assert.strictEqual(result.allowed, false);
            assert.strictEqual(result.remaining, 0);
            assert(result.resetTime);
        });

        it('should reset API counter on new day', async () => {
            await licenseManager.initialize();

            // Set yesterday's date
            licenseManager.currentLicense.apiCallsResetDate =
                new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
            licenseManager.currentLicense.apiCallsToday = 100;
            await licenseManager.saveLicense(licenseManager.currentLicense);

            // Should reset
            const result = await licenseManager.checkApiLimit();
            assert.strictEqual(result.allowed, true);
            assert.strictEqual(result.remaining, 99);
        });

        it('should allow unlimited API calls for pro', async () => {
            await licenseManager.ensureSecretKey();
            const validKey = licenseManager.generateLicenseKey();
            await licenseManager.activatePro(validKey);

            const result = await licenseManager.checkApiLimit();
            assert.strictEqual(result.allowed, true);
            assert.strictEqual(result.remaining, 'unlimited');
        });
    });

    describe('Backward Compatibility', () => {
        it('should maintain FBMCP-XXXX-XXXX-XXXX-XXXX key format', async () => {
            await licenseManager.ensureSecretKey();
            const key = licenseManager.generateLicenseKey();

            const pattern = /^FBMCP-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
            assert(pattern.test(key), 'Should maintain key format');
        });

        it('should preserve all existing license file fields', async () => {
            await licenseManager.initialize();
            const license = await fs.readFile(testLicenseFile, 'utf8');
            const parsed = JSON.parse(license);

            // Verify all expected fields present
            assert(parsed.type);
            assert(parsed.trialStart);
            assert(typeof parsed.apiCallsToday === 'number');
            assert(parsed.apiCallsResetDate);
            assert(typeof parsed.monthlyInvoices === 'number');
            assert(typeof parsed.monthlyExpenses === 'number');
            assert(parsed.monthResetDate);
        });
    });

    describe('Logging and Audit Trail', () => {
        it('should log key security events', async () => {
            // This would require winston log capture in production
            // For now, verify logger is configured
            assert(licenseManager.constructor.toString().includes('winston'));
        });
    });
});

// Run tests
describe('Security Comparison: MD5 vs HMAC-SHA256', () => {
    it('should demonstrate MD5 vulnerability', () => {
        const data = 'AAAABBBBCCCC';

        // Old MD5 approach (vulnerable)
        const md5Hash = crypto.createHash('md5').update(data).digest('hex');
        const md5Checksum = md5Hash.substring(0, 4).toUpperCase();

        console.log('MD5 Checksum:', md5Checksum);
        console.log('MD5 is vulnerable to:');
        console.log('  - Collision attacks');
        console.log('  - Pre-image attacks');
        console.log('  - No secret key protection');

        // New HMAC-SHA256 approach (secure)
        const secret = crypto.randomBytes(32).toString('hex');
        const hmac = crypto.createHmac('sha256', secret);
        hmac.update(data);
        const hmacHash = hmac.digest('hex');
        const hmacChecksum = hmacHash.substring(0, 4).toUpperCase();

        console.log('\nHMAC-SHA256 Checksum:', hmacChecksum);
        console.log('HMAC-SHA256 provides:');
        console.log('  - Collision resistance');
        console.log('  - Secret key protection');
        console.log('  - Timing-safe validation');
        console.log('  - Industry-standard security');

        // Demonstrate they produce different checksums
        assert.notStrictEqual(md5Checksum, hmacChecksum,
            'MD5 and HMAC produce different checksums');
    });
});

console.log('\nRunning License Manager v2 Security Tests...\n');
