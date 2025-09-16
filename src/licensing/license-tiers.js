// Revised Trial vs Pro Feature Tiers
// Trial: Read-only to demonstrate value
// Pro: Full functionality

const FEATURE_TIERS = {
    trial: {
        name: 'Trial',
        duration: 30, // days
        features: {
            // All read operations allowed
            read: {
                clients: true,
                invoices: true,
                expenses: true,
                payments: true,
                estimates: true,
                projects: true,
                timeEntries: true,
                items: true,
                taxes: true,
                categories: true,
                reports: true,
                staff: true,
                recurring: true,
                creditNotes: true
            },
            // No write operations
            write: {
                clients: false,
                invoices: false,
                expenses: false,
                payments: false,
                estimates: false,
                projects: false,
                timeEntries: false,
                items: false,
                taxes: false,
                categories: false,
                recurring: false,
                creditNotes: false,
                staff: false
            },
            // Limited export
            export: {
                csv: true,
                pdf: false,
                excel: false
            },
            // No AI features
            ai: {
                categorization: false,
                fraudDetection: false,
                reconciliation: false,
                insights: false
            }
        },
        limits: {
            apiCallsPerDay: null, // Unlimited read calls
            exportPerMonth: 10
        }
    },
    
    pro: {
        name: 'Pro',
        features: {
            // Everything unlocked
            read: true,  // All read operations
            write: true, // All write operations
            export: true, // All export formats
            ai: {
                categorization: true,
                fraudDetection: true,
                reconciliation: true,
                insights: true,
                batchProcessing: true
            }
        },
        limits: {
            apiCallsPerDay: null, // Unlimited
            exportPerMonth: null  // Unlimited
        }
    }
};

class SimplifiedLicenseManager {
    constructor() {
        this.tier = 'trial';
        this.trialStartDate = null;
    }
    
    async checkAccess(operation, resource) {
        // Parse operation type
        const [action, entity] = operation.split('_'); // e.g., 'read_invoices'
        
        if (this.tier === 'pro') {
            return { allowed: true, tier: 'pro' };
        }
        
        // Trial mode
        const trialFeatures = FEATURE_TIERS.trial.features;
        
        if (action === 'read' && trialFeatures.read[entity]) {
            return { 
                allowed: true, 
                tier: 'trial',
                message: 'Read-only access in trial mode'
            };
        }
        
        if (action === 'write') {
            return {
                allowed: false,
                tier: 'trial',
                upgradeRequired: true,
                message: `Creating or editing ${entity} requires Pro version`,
                upgradeUrl: 'https://freshbooks-mcp.com/upgrade'
            };
        }
        
        // AI features
        if (action === 'ai') {
            return {
                allowed: false,
                tier: 'trial', 
                upgradeRequired: true,
                message: 'AI-powered features require Pro version',
                features: ['Smart categorization', 'Fraud detection', 'Bank reconciliation'],
                upgradeUrl: 'https://freshbooks-mcp.com/upgrade'
            };
        }
        
        return { allowed: true, tier: 'trial' };
    }
}

module.exports = SimplifiedLicenseManager;