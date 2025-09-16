// FreshBooks MCP License Manager
// Handles Trial vs Pro tier feature gating

const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');

class LicenseManager {
    constructor() {
        this.licenseFile = path.join(os.homedir(), '.freshbooks-mcp', 'license.json');
        this.currentLicense = null;
        this.trialStartDate = null;
        this.apiCallCount = 0;
        this.monthlyLimits = {
            invoices: 0,
            expenses: 0
        };
    }

    async initialize() {
        try {
            await this.loadLicense();
        } catch (error) {
            // No license file, start trial
            await this.startTrial();
        }
    }

    async loadLicense() {
        const data = await fs.readFile(this.licenseFile, 'utf8');
        const license = JSON.parse(data);
        
        if (license.type === 'trial') {
            const trialEnd = new Date(license.trialStart);
            trialEnd.setDate(trialEnd.getDate() + 30);
            
            if (new Date() > trialEnd) {
                throw new Error('Trial expired');
            }
        } else if (license.type === 'pro') {
            // Validate pro license
            if (!this.validateLicenseKey(license.key)) {
                throw new Error('Invalid license key');
            }
        }
        
        this.currentLicense = license;
        return license;
    }

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
        return trial;
    }

    async activatePro(licenseKey) {
        if (!this.validateLicenseKey(licenseKey)) {
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
        return proLicense;
    }

    validateLicenseKey(key) {
        // License key format: FBMCP-XXXX-XXXX-XXXX-XXXX
        const keyPattern = /^FBMCP-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
        if (!keyPattern.test(key)) return false;
        
        // Validate checksum (simplified for demo)
        const parts = key.split('-');
        const checksum = parts.slice(1, 4).join('');
        const hash = crypto.createHash('md5').update(checksum).digest('hex');
        const expectedLast = hash.substring(0, 4).toUpperCase();
        
        return parts[4] === expectedLast;
    }

    extractEmailFromKey(key) {
        // In production, this would query your licensing server
        return 'user@example.com';
    }

    async saveLicense(license) {
        const dir = path.dirname(this.licenseFile);
        await fs.mkdir(dir, { recursive: true });
        await fs.writeFile(this.licenseFile, JSON.stringify(license, null, 2));
    }

    async checkFeatureAccess(feature) {
        if (!this.currentLicense) {
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
            return { allowed: await access(), tier: 'trial' };
        }
        
        return { 
            allowed: access === true, 
            tier: 'trial',
            upgradeRequired: access === false
        };
    }

    async checkMonthlyLimit(type, limit) {
        const now = new Date();
        const resetDate = new Date(this.currentLicense.monthResetDate);
        
        // Reset monthly counters if new month
        if (now.getMonth() !== resetDate.getMonth() || now.getFullYear() !== resetDate.getFullYear()) {
            this.currentLicense.monthlyInvoices = 0;
            this.currentLicense.monthlyExpenses = 0;
            this.currentLicense.monthResetDate = now.toISOString();
            await this.saveLicense(this.currentLicense);
        }
        
        const currentCount = type === 'invoices' 
            ? this.currentLicense.monthlyInvoices 
            : this.currentLicense.monthlyExpenses;
            
        if (currentCount >= limit) {
            return false;
        }
        
        // Increment counter
        if (type === 'invoices') {
            this.currentLicense.monthlyInvoices++;
        } else {
            this.currentLicense.monthlyExpenses++;
        }
        
        await this.saveLicense(this.currentLicense);
        return true;
    }

    async checkApiLimit() {
        if (this.currentLicense.type === 'pro') {
            return { allowed: true, remaining: 'unlimited' };
        }
        
        const now = new Date();
        const resetDate = new Date(this.currentLicense.apiCallsResetDate);
        
        // Reset daily counter if new day
        if (now.toDateString() !== resetDate.toDateString()) {
            this.currentLicense.apiCallsToday = 0;
            this.currentLicense.apiCallsResetDate = now.toISOString();
            await this.saveLicense(this.currentLicense);
        }
        
        const limit = 100; // Trial limit
        const used = this.currentLicense.apiCallsToday;
        
        if (used >= limit) {
            return { 
                allowed: false, 
                remaining: 0,
                resetTime: this.getNextResetTime()
            };
        }
        
        this.currentLicense.apiCallsToday++;
        await this.saveLicense(this.currentLicense);
        
        return { 
            allowed: true, 
            remaining: limit - used - 1
        };
    }

    getNextResetTime() {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        tomorrow.setHours(0, 0, 0, 0);
        return tomorrow.toISOString();
    }

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
            
            info.trialDaysRemaining = Math.ceil((trialEnd - new Date()) / (1000 * 60 * 60 * 24));
            info.apiCallsToday = this.currentLicense.apiCallsToday;
            info.apiCallsRemaining = 100 - this.currentLicense.apiCallsToday;
            info.monthlyInvoicesUsed = this.currentLicense.monthlyInvoices;
            info.monthlyExpensesUsed = this.currentLicense.monthlyExpenses;
        } else {
            info.activatedDate = this.currentLicense.activatedDate;
            info.email = this.currentLicense.email;
        }
        
        return info;
    }
}

module.exports = new LicenseManager();