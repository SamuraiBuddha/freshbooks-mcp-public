// FreshBooks MCP License Manager - Enhanced Security Version
// Upgraded from MD5 to HMAC-SHA256 for license validation
// Version: 2.0.0 - Security Hardened

const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');
const winston = require('winston');

// Configure logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({
            filename: path.join(os.homedir(), '.freshbooks-mcp', 'license-manager.log')
        })
    ]
});

/**
 * LicenseManager - Handles Trial vs Pro tier feature gating with secure HMAC-SHA256 validation
 * @class
 */
class LicenseManager {
    /**
     * Initialize License Manager
     * @param {Object} config - Configuration options
     * @param {string} config.licenseFile - Custom license file path (optional)
     * @param {string} config.secretKeyFile - Custom secret key file path (optional)
     */
    constructor(config = {}) {
        const baseDir = path.join(os.homedir(), '.freshbooks-mcp');

        this.licenseFile = config.licenseFile || path.join(baseDir, 'license.json');
        this.secretKeyFile = config.secretKeyFile || path.join(baseDir, '.license-secret');
        this.currentLicense = null;
        this.trialStartDate = null;
        this.apiCallCount = 0;
        this.monthlyLimits = {
            invoices: 0,
            expenses: 0
        };
        this.secretKey = null;

        logger.info('LicenseManager initialized', {
            licenseFile: this.licenseFile,
            timestamp: new Date().toISOString()
        });
    }

    /**
     * Initialize license system - load existing license or start trial
     * @returns {Promise<void>}
     */
    async initialize() {
        try {
            await this.ensureSecretKey();
            await this.loadLicense();
            logger.info('License loaded successfully', {
                type: this.currentLicense?.type
            });
        } catch (error) {
            logger.warn('No valid license found, starting trial', {
                error: error.message
            });
            // No license file or invalid, start trial
            await this.startTrial();
        }
    }

    /**
     * Ensure HMAC secret key exists, generate if missing
     * @returns {Promise<void>}
     * @private
     */
    async ensureSecretKey() {
        try {
            // Try to load existing secret key
            const keyData = await fs.readFile(this.secretKeyFile, 'utf8');
            this.secretKey = keyData.trim();

            if (this.secretKey.length < 32) {
                throw new Error('Secret key too short');
            }

            logger.info('Secret key loaded successfully');
        } catch (error) {
            logger.info('Generating new secret key', { reason: error.message });
            // Generate new secure secret key
            this.secretKey = crypto.randomBytes(64).toString('hex');

            // Save secret key with restricted permissions
            const dir = path.dirname(this.secretKeyFile);
            await fs.mkdir(dir, { recursive: true });
            await fs.writeFile(this.secretKeyFile, this.secretKey, {
                mode: 0o600  // Owner read/write only
            });

            logger.info('New secret key generated and saved');
        }
    }

    /**
     * Load and validate license file
     * @returns {Promise<Object>} License object
     * @throws {Error} If license is invalid or expired
     */
    async loadLicense() {
        let data;
        try {
            data = await fs.readFile(this.licenseFile, 'utf8');
        } catch (error) {
            logger.error('Failed to read license file', {
                error: error.message,
                path: this.licenseFile
            });
            throw new Error('License file not found');
        }

        let license;
        try {
            license = JSON.parse(data);
        } catch (error) {
            logger.error('Failed to parse license file - corrupted JSON', {
                error: error.message
            });
            throw new Error('License file corrupted');
        }

        // Validate license structure
        if (!license || typeof license !== 'object') {
            logger.error('Invalid license structure');
            throw new Error('Invalid license format');
        }

        if (!license.type || !['trial', 'pro'].includes(license.type)) {
            logger.error('Invalid license type', { type: license.type });
            throw new Error('Invalid license type');
        }

        if (license.type === 'trial') {
            if (!license.trialStart) {
                logger.error('Trial license missing trialStart date');
                throw new Error('Invalid trial license');
            }

            const trialEnd = new Date(license.trialStart);
            trialEnd.setDate(trialEnd.getDate() + 30);

            if (new Date() > trialEnd) {
                logger.warn('Trial license expired', {
                    trialStart: license.trialStart,
                    trialEnd: trialEnd.toISOString()
                });
                throw new Error('Trial expired');
            }
        } else if (license.type === 'pro') {
            // Validate pro license
            if (!license.key || typeof license.key !== 'string') {
                logger.error('Pro license missing key');
                throw new Error('Invalid pro license');
            }

            if (!this.validateLicenseKey(license.key)) {
                logger.error('Pro license key validation failed', {
                    key: license.key.substring(0, 15) + '...'
                });
                throw new Error('Invalid license key');
            }
        }

        this.currentLicense = license;
        logger.info('License validated successfully', {
            type: license.type
        });
        return license;
    }

    /**
     * Start a new trial license
     * @returns {Promise<Object>} Trial license object
     */
    async startTrial() {
        const trial = {
            type: 'trial',
            trialStart: new Date().toISOString(),
            apiCallsToday: 0,
            apiCallsResetDate: new Date().toISOString(),
            monthlyInvoices: 0,
            monthlyExpenses: 0,
            monthResetDate: new Date().toISOString()
        };

        await this.saveLicense(trial);
        this.currentLicense = trial;

        logger.info('Trial license created', {
            trialStart: trial.trialStart
        });
        return trial;
    }

    /**
     * Activate a pro license with the provided key
     * @param {string} licenseKey - License key in format FBMCP-XXXX-XXXX-XXXX-XXXX
     * @returns {Promise<Object>} Pro license object
     * @throws {Error} If license key is invalid
     */
    async activatePro(licenseKey) {
        if (!licenseKey || typeof licenseKey !== 'string') {
            logger.error('Invalid license key parameter type');
            throw new Error('Invalid license key format');
        }

        if (!this.validateLicenseKey(licenseKey)) {
            logger.error('License key validation failed during activation');
            throw new Error('Invalid license key');
        }

        const proLicense = {
            type: 'pro',
            key: licenseKey,
            activatedDate: new Date().toISOString(),
            email: this.extractEmailFromKey(licenseKey)
        };

        await this.saveLicense(proLicense);
        this.currentLicense = proLicense;

        logger.info('Pro license activated', {
            activatedDate: proLicense.activatedDate
        });
        return proLicense;
    }

    /**
     * Validate license key using HMAC-SHA256
     * @param {string} key - License key to validate
     * @returns {boolean} True if valid, false otherwise
     */
    validateLicenseKey(key) {
        try {
            // License key format: FBMCP-XXXX-XXXX-XXXX-XXXX
            const keyPattern = /^FBMCP-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
            if (!keyPattern.test(key)) {
                logger.warn('License key failed pattern validation', {
                    keyPrefix: key?.substring(0, 10)
                });
                return false;
            }

            const parts = key.split('-');
            if (parts.length !== 5) {
                logger.warn('License key has incorrect number of segments');
                return false;
            }

            // Validate HMAC-SHA256 checksum
            const dataSegments = parts.slice(1, 4).join('');
            const providedChecksum = parts[4];

            // Generate HMAC-SHA256 hash
            const hmac = crypto.createHmac('sha256', this.secretKey);
            hmac.update(dataSegments);
            const computedHash = hmac.digest('hex');

            // Take first 4 characters of hash for checksum (matches format)
            const expectedChecksum = computedHash.substring(0, 4).toUpperCase();

            // Timing-safe comparison to prevent timing attacks
            const isValid = crypto.timingSafeEqual(
                Buffer.from(providedChecksum),
                Buffer.from(expectedChecksum)
            );

            if (!isValid) {
                logger.warn('License key HMAC checksum mismatch', {
                    expected: expectedChecksum,
                    provided: providedChecksum
                });
            }

            return isValid;
        } catch (error) {
            logger.error('License key validation error', {
                error: error.message
            });
            return false;
        }
    }

    /**
     * Extract email from license key (placeholder for server lookup)
     * @param {string} key - License key
     * @returns {string} Email address
     * @private
     */
    extractEmailFromKey(key) {
        // In production, this would query your licensing server
        // For now, return placeholder
        logger.info('Email extraction requested for license key');
        return 'user@example.com';
    }

    /**
     * Save license to file
     * @param {Object} license - License object to save
     * @returns {Promise<void>}
     * @private
     */
    async saveLicense(license) {
        try {
            const dir = path.dirname(this.licenseFile);
            await fs.mkdir(dir, { recursive: true });
            await fs.writeFile(
                this.licenseFile,
                JSON.stringify(license, null, 2),
                { mode: 0o600 }  // Owner read/write only
            );
            logger.info('License saved successfully', {
                type: license.type
            });
        } catch (error) {
            logger.error('Failed to save license file', {
                error: error.message
            });
            throw error;
        }
    }

    /**
     * Check if user has access to a specific feature
     * @param {string} feature - Feature name to check
     * @returns {Promise<Object>} Access result with allowed status and tier
     */
    async checkFeatureAccess(feature) {
        if (!this.currentLicense) {
            logger.info('License not initialized, initializing now');
            await this.initialize();
        }

        const tier = this.currentLicense.type;

        // Pro has access to everything
        if (tier === 'pro') {
            return { allowed: true, tier: 'pro' };
        }

        // Trial tier restrictions
        const trialFeatures = {
            // Read operations - always allowed
            'read_clients': true,
            'read_invoices': true,
            'read_expenses': true,
            'read_payments': true,
            'read_estimates': true,
            'read_reports': true,
            'read_items': true,
            'read_taxes': true,
            'read_categories': true,
            'read_time_entries': true,
            'read_projects': true,

            // Limited write operations
            'write_invoice': () => this.checkMonthlyLimit('invoices', 5),
            'write_expense': () => this.checkMonthlyLimit('expenses', 10),

            // Pro-only features
            'write_client': false,
            'write_payment': false,
            'write_estimate': false,
            'write_project': false,
            'write_time_entry': false,
            'write_item': false,
            'write_tax': false,
            'write_recurring': false,
            'write_credit_note': false,
            'write_staff': false,
            'write_category': false
        };

        const access = trialFeatures[feature];

        if (typeof access === 'function') {
            const allowed = await access();
            logger.info('Feature access checked (limited)', {
                feature,
                allowed,
                tier
            });
            return { allowed, tier: 'trial' };
        }

        const result = {
            allowed: access === true,
            tier: 'trial',
            upgradeRequired: access === false
        };

        logger.info('Feature access checked', {
            feature,
            allowed: result.allowed,
            tier
        });
        return result;
    }

    /**
     * Check if monthly limit is reached for a feature
     * @param {string} type - Type of limit (invoices or expenses)
     * @param {number} limit - Monthly limit threshold
     * @returns {Promise<boolean>} True if under limit, false otherwise
     * @private
     */
    async checkMonthlyLimit(type, limit) {
        const now = new Date();
        const resetDate = new Date(this.currentLicense.monthResetDate);

        // Reset monthly counters if new month
        if (now.getMonth() !== resetDate.getMonth() ||
            now.getFullYear() !== resetDate.getFullYear()) {

            logger.info('Resetting monthly limits for new month', {
                previousResetDate: resetDate.toISOString(),
                newResetDate: now.toISOString()
            });

            this.currentLicense.monthlyInvoices = 0;
            this.currentLicense.monthlyExpenses = 0;
            this.currentLicense.monthResetDate = now.toISOString();
            await this.saveLicense(this.currentLicense);
        }

        const currentCount = type === 'invoices'
            ? this.currentLicense.monthlyInvoices
            : this.currentLicense.monthlyExpenses;

        if (currentCount >= limit) {
            logger.warn('Monthly limit reached', {
                type,
                limit,
                currentCount
            });
            return false;
        }

        // Increment counter
        if (type === 'invoices') {
            this.currentLicense.monthlyInvoices++;
        } else {
            this.currentLicense.monthlyExpenses++;
        }

        await this.saveLicense(this.currentLicense);

        logger.info('Monthly limit checked', {
            type,
            currentCount: currentCount + 1,
            limit
        });
        return true;
    }

    /**
     * Check if daily API limit is reached
     * @returns {Promise<Object>} API limit status with remaining calls
     */
    async checkApiLimit() {
        if (this.currentLicense.type === 'pro') {
            return { allowed: true, remaining: 'unlimited' };
        }

        const now = new Date();
        const resetDate = new Date(this.currentLicense.apiCallsResetDate);

        // Reset daily counter if new day
        if (now.toDateString() !== resetDate.toDateString()) {
            logger.info('Resetting API call counter for new day', {
                previousResetDate: resetDate.toISOString(),
                newResetDate: now.toISOString()
            });

            this.currentLicense.apiCallsToday = 0;
            this.currentLicense.apiCallsResetDate = now.toISOString();
            await this.saveLicense(this.currentLicense);
        }

        const limit = 100; // Trial limit
        const used = this.currentLicense.apiCallsToday;

        if (used >= limit) {
            logger.warn('Daily API limit reached', {
                used,
                limit
            });
            return {
                allowed: false,
                remaining: 0,
                resetTime: this.getNextResetTime()
            };
        }

        this.currentLicense.apiCallsToday++;
        await this.saveLicense(this.currentLicense);

        logger.info('API call recorded', {
            used: used + 1,
            remaining: limit - used - 1
        });

        return {
            allowed: true,
            remaining: limit - used - 1
        };
    }

    /**
     * Get the next reset time for API limits (midnight)
     * @returns {string} ISO timestamp of next reset
     * @private
     */
    getNextResetTime() {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        tomorrow.setHours(0, 0, 0, 0);
        return tomorrow.toISOString();
    }

    /**
     * Get current license information
     * @returns {Promise<Object>} License info object
     */
    async getLicenseInfo() {
        if (!this.currentLicense) {
            await this.initialize();
        }

        const info = {
            type: this.currentLicense.type,
            status: 'active'
        };

        if (this.currentLicense.type === 'trial') {
            const trialEnd = new Date(this.currentLicense.trialStart);
            trialEnd.setDate(trialEnd.getDate() + 30);

            info.trialDaysRemaining = Math.ceil(
                (trialEnd - new Date()) / (1000 * 60 * 60 * 24)
            );
            info.apiCallsToday = this.currentLicense.apiCallsToday;
            info.apiCallsRemaining = 100 - this.currentLicense.apiCallsToday;
            info.monthlyInvoicesUsed = this.currentLicense.monthlyInvoices;
            info.monthlyExpensesUsed = this.currentLicense.monthlyExpenses;
        } else {
            info.activatedDate = this.currentLicense.activatedDate;
            info.email = this.currentLicense.email;
        }

        logger.info('License info retrieved', {
            type: info.type,
            status: info.status
        });
        return info;
    }

    /**
     * Generate a valid license key (for testing/key generation)
     * @param {string} dataSegment - Data to encode in license key
     * @returns {string} Generated license key
     */
    generateLicenseKey(dataSegment = null) {
        if (!dataSegment) {
            // Generate random data segments
            const segment1 = crypto.randomBytes(2).toString('hex').toUpperCase();
            const segment2 = crypto.randomBytes(2).toString('hex').toUpperCase();
            const segment3 = crypto.randomBytes(2).toString('hex').toUpperCase();
            dataSegment = segment1 + segment2 + segment3;
        }

        // Generate HMAC-SHA256 checksum
        const hmac = crypto.createHmac('sha256', this.secretKey);
        hmac.update(dataSegment);
        const hash = hmac.digest('hex');
        const checksum = hash.substring(0, 4).toUpperCase();

        // Format: FBMCP-XXXX-XXXX-XXXX-XXXX
        const part1 = dataSegment.substring(0, 4);
        const part2 = dataSegment.substring(4, 8);
        const part3 = dataSegment.substring(8, 12);

        const licenseKey = `FBMCP-${part1}-${part2}-${part3}-${checksum}`;

        logger.info('License key generated', {
            keyPrefix: licenseKey.substring(0, 15)
        });
        return licenseKey;
    }
}

module.exports = new LicenseManager();
