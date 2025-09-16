// Feature Gating Middleware for FreshBooks MCP
// Intercepts API calls and enforces Trial vs Pro limitations

const licenseManager = require('./license-manager');

class FeatureGate {
    constructor() {
        this.initialized = false;
    }

    async initialize() {
        if (!this.initialized) {
            await licenseManager.initialize();
            this.initialized = true;
        }
    }

    // Middleware for Express/Connect
    middleware() {
        return async (req, res, next) => {
            await this.initialize();
            
            // Extract command from request
            const command = this.extractCommand(req);
            
            if (!command) {
                return next();
            }
            
            // Check API rate limit first
            const apiLimit = await licenseManager.checkApiLimit();
            if (!apiLimit.allowed) {
                return res.status(429).json({
                    error: 'API rate limit exceeded',
                    message: 'Trial accounts are limited to 100 API calls per day',
                    resetTime: apiLimit.resetTime,
                    upgradeUrl: 'https://freshbooks-mcp.com/upgrade'
                });
            }
            
            // Check feature access
            const access = await licenseManager.checkFeatureAccess(command);
            
            if (!access.allowed) {
                if (access.upgradeRequired) {
                    return res.status(402).json({
                        error: 'Pro feature required',
                        message: `The ${command} feature requires a Pro subscription`,
                        tier: 'trial',
                        upgradeUrl: 'https://freshbooks-mcp.com/upgrade'
                    });
                } else {
                    // Monthly limit reached
                    return res.status(429).json({
                        error: 'Monthly limit reached',
                        message: this.getLimitMessage(command),
                        tier: 'trial',
                        upgradeUrl: 'https://freshbooks-mcp.com/upgrade'
                    });
                }
            }
            
            // Add license info to request
            req.licenseInfo = await licenseManager.getLicenseInfo();
            req.remainingApiCalls = apiLimit.remaining;
            
            next();
        };
    }

    // MCP Server integration
    async checkMcpAccess(method, params) {
        await this.initialize();
        
        // Map MCP method to feature
        const command = this.mapMcpMethod(method);
        
        // Check API limit
        const apiLimit = await licenseManager.checkApiLimit();
        if (!apiLimit.allowed) {
            throw new Error(`API rate limit exceeded. Trial accounts are limited to 100 calls/day. Resets at ${apiLimit.resetTime}`);
        }
        
        // Check feature access
        const access = await licenseManager.checkFeatureAccess(command);
        
        if (!access.allowed) {
            if (access.upgradeRequired) {
                throw new Error(`Pro feature required: ${command} is only available in Pro version. Upgrade at https://freshbooks-mcp.com/upgrade`);
            } else {
                throw new Error(this.getLimitMessage(command));
            }
        }
        
        return {
            allowed: true,
            tier: access.tier,
            remainingApiCalls: apiLimit.remaining
        };
    }

    extractCommand(req) {
        // Extract from various request formats
        if (req.body && req.body.command) {
            return req.body.command;
        }
        if (req.params && req.params.command) {
            return req.params.command;
        }
        if (req.query && req.query.command) {
            return req.query.command;
        }
        
        // Extract from path
        const path = req.path || req.url;
        const match = path.match(/\/api\/(\w+)/);
        return match ? match[1] : null;
    }

    mapMcpMethod(method) {
        // Map MCP method names to our feature names
        const mapping = {
            'freshbooks.listClients': 'read_clients',
            'freshbooks.createClient': 'write_client',
            'freshbooks.listInvoices': 'read_invoices',
            'freshbooks.createInvoice': 'write_invoice',
            'freshbooks.listExpenses': 'read_expenses',
            'freshbooks.createExpense': 'write_expense',
            'freshbooks.listPayments': 'read_payments',
            'freshbooks.createPayment': 'write_payment',
            'freshbooks.listEstimates': 'read_estimates',
            'freshbooks.createEstimate': 'write_estimate',
            'freshbooks.listProjects': 'read_projects',
            'freshbooks.createProject': 'write_project',
            'freshbooks.listTimeEntries': 'read_time_entries',
            'freshbooks.createTimeEntry': 'write_time_entry',
            'freshbooks.listItems': 'read_items',
            'freshbooks.createItem': 'write_item',
            'freshbooks.listTaxes': 'read_taxes',
            'freshbooks.createTax': 'write_tax',
            'freshbooks.listCategories': 'read_categories',
            'freshbooks.createCategory': 'write_category',
            'freshbooks.listRecurring': 'read_recurring',
            'freshbooks.createRecurring': 'write_recurring',
            'freshbooks.listCreditNotes': 'read_credit_notes',
            'freshbooks.createCreditNote': 'write_credit_note',
            'freshbooks.listStaff': 'read_staff',
            'freshbooks.createStaff': 'write_staff',
            'freshbooks.getReports': 'read_reports'
        };
        
        return mapping[method] || method.replace('freshbooks.', '').toLowerCase();
    }

    getLimitMessage(command) {
        if (command === 'write_invoice') {
            return 'Trial accounts are limited to 5 invoices per month. Upgrade to Pro for unlimited invoicing.';
        }
        if (command === 'write_expense') {
            return 'Trial accounts are limited to 10 expenses per month. Upgrade to Pro for unlimited expense tracking.';
        }
        return `Monthly limit reached for ${command}. Upgrade to Pro for unlimited access.`;
    }

    // CLI integration
    async validateCliCommand(command, args) {
        await this.initialize();
        
        const licenseInfo = await licenseManager.getLicenseInfo();
        
        // Show license status
        if (command === 'license' || command === 'status') {
            return {
                success: true,
                data: licenseInfo
            };
        }
        
        // Handle activation
        if (command === 'activate' && args.key) {
            try {
                const result = await licenseManager.activatePro(args.key);
                return {
                    success: true,
                    message: 'Pro license activated successfully!',
                    data: result
                };
            } catch (error) {
                return {
                    success: false,
                    error: error.message
                };
            }
        }
        
        // Check feature access for other commands
        const access = await this.checkMcpAccess(command, args);
        return access;
    }
}

module.exports = new FeatureGate();