// Port Manager for FreshBooks MCP
// Handles port conflict resolution and dynamic port allocation

const net = require('net');
const fs = require('fs').promises;
const path = require('path');

class PortManager {
    constructor() {
        this.configFile = path.join(process.env.APPDATA || process.env.HOME, 'FreshBooksMCP', 'port-config.json');
        this.defaultPorts = {
            vllm: 8000,
            ollama: 11434,
            lmstudio: 1234,
            llamacpp: 8080
        };
        this.portRanges = {
            vllm: { min: 8000, max: 8099 },
            ollama: { min: 11434, max: 11534 },
            lmstudio: { min: 1234, max: 1334 },
            llamacpp: { min: 8080, max: 8180 }
        };
        this.allocatedPorts = {};
        this.knownServices = {
            1234: 'LM Studio',
            11434: 'Ollama',
            8000: 'vLLM',
            8080: 'HTTP Alternative',
            5000: 'Flask/Python',
            3000: 'Node.js',
            8888: 'Jupyter'
        };
    }

    async initialize() {
        // Load saved port configuration
        await this.loadConfig();
        
        // Validate and update port allocations
        await this.validatePorts();
    }

    async loadConfig() {
        try {
            const configDir = path.dirname(this.configFile);
            await fs.mkdir(configDir, { recursive: true });
            
            const data = await fs.readFile(this.configFile, 'utf8');
            const config = JSON.parse(data);
            this.allocatedPorts = config.allocatedPorts || {};
        } catch (error) {
            // No config file yet, use defaults
            this.allocatedPorts = {};
        }
    }

    async saveConfig() {
        const configDir = path.dirname(this.configFile);
        await fs.mkdir(configDir, { recursive: true });
        
        const config = {
            allocatedPorts: this.allocatedPorts,
            timestamp: new Date().toISOString()
        };
        
        await fs.writeFile(this.configFile, JSON.stringify(config, null, 2));
    }

    async isPortAvailable(port, host = '127.0.0.1') {
        return new Promise((resolve) => {
            const server = net.createServer();
            
            server.once('error', (err) => {
                if (err.code === 'EADDRINUSE') {
                    resolve(false);
                } else {
                    resolve(false); // Treat other errors as port unavailable
                }
            });
            
            server.once('listening', () => {
                server.close();
                resolve(true);
            });
            
            server.listen(port, host);
        });
    }

    async findAvailablePort(service, preferredPort = null) {
        // Try preferred port first
        if (preferredPort && await this.isPortAvailable(preferredPort)) {
            return preferredPort;
        }
        
        // Try default port
        const defaultPort = this.defaultPorts[service];
        if (defaultPort && await this.isPortAvailable(defaultPort)) {
            return defaultPort;
        }
        
        // Search in the service's port range
        const range = this.portRanges[service];
        if (range) {
            for (let port = range.min; port <= range.max; port++) {
                if (await this.isPortAvailable(port)) {
                    return port;
                }
            }
        }
        
        // Fallback: search in general range
        for (let port = 9000; port <= 9999; port++) {
            if (await this.isPortAvailable(port)) {
                return port;
            }
        }
        
        throw new Error(`No available ports found for service: ${service}`);
    }

    async allocatePort(service, preferredPort = null) {
        // Check if already allocated
        if (this.allocatedPorts[service]) {
            const allocatedPort = this.allocatedPorts[service];
            if (await this.isPortAvailable(allocatedPort)) {
                return allocatedPort;
            }
            // Port no longer available, find new one
            console.log(`Previously allocated port ${allocatedPort} for ${service} is now in use, finding alternative...`);
        }
        
        const port = await this.findAvailablePort(service, preferredPort);
        this.allocatedPorts[service] = port;
        await this.saveConfig();
        
        return port;
    }

    async detectConflicts() {
        const conflicts = [];
        
        for (const [service, defaultPort] of Object.entries(this.defaultPorts)) {
            if (!(await this.isPortAvailable(defaultPort))) {
                const occupant = await this.identifyPortOccupant(defaultPort);
                conflicts.push({
                    service,
                    port: defaultPort,
                    occupiedBy: occupant,
                    allocated: this.allocatedPorts[service]
                });
            }
        }
        
        return conflicts;
    }

    async identifyPortOccupant(port) {
        // Check known services
        if (this.knownServices[port]) {
            return this.knownServices[port];
        }
        
        // Try to identify via process (Windows-specific)
        try {
            const { exec } = require('child_process').promises;
            const { stdout } = await exec(`netstat -ano | findstr :${port}`);
            const lines = stdout.trim().split('\n');
            
            if (lines.length > 0) {
                // Extract PID from netstat output
                const parts = lines[0].trim().split(/\s+/);
                const pid = parts[parts.length - 1];
                
                // Get process name from PID
                const { stdout: processInfo } = await exec(`tasklist /FI "PID eq ${pid}" /FO CSV`);
                const processLines = processInfo.trim().split('\n');
                if (processLines.length > 1) {
                    const processName = processLines[1].split(',')[0].replace(/"/g, '');
                    return `${processName} (PID: ${pid})`;
                }
            }
        } catch (error) {
            // Fall back to generic description
        }
        
        return 'Unknown Service';
    }

    async validatePorts() {
        const validation = {
            valid: [],
            conflicts: [],
            reallocated: []
        };
        
        for (const [service, port] of Object.entries(this.allocatedPorts)) {
            if (await this.isPortAvailable(port)) {
                validation.valid.push({ service, port });
            } else {
                const newPort = await this.findAvailablePort(service);
                this.allocatedPorts[service] = newPort;
                validation.reallocated.push({ 
                    service, 
                    oldPort: port, 
                    newPort,
                    reason: await this.identifyPortOccupant(port)
                });
            }
        }
        
        if (validation.reallocated.length > 0) {
            await this.saveConfig();
        }
        
        return validation;
    }

    async getPortsStatus() {
        const status = {
            allocated: this.allocatedPorts,
            available: {},
            occupied: {}
        };
        
        for (const [service, defaultPort] of Object.entries(this.defaultPorts)) {
            const isAvailable = await this.isPortAvailable(defaultPort);
            if (isAvailable) {
                status.available[service] = defaultPort;
            } else {
                status.occupied[service] = {
                    port: defaultPort,
                    occupiedBy: await this.identifyPortOccupant(defaultPort)
                };
            }
        }
        
        return status;
    }

    async suggestPortConfiguration() {
        const suggestions = {};
        const conflicts = await this.detectConflicts();
        
        for (const conflict of conflicts) {
            const availablePort = await this.findAvailablePort(conflict.service);
            suggestions[conflict.service] = {
                currentDefault: conflict.port,
                occupiedBy: conflict.occupiedBy,
                suggestedPort: availablePort,
                reason: `Port ${conflict.port} is occupied by ${conflict.occupiedBy}`
            };
        }
        
        return suggestions;
    }

    async releasePort(service) {
        if (this.allocatedPorts[service]) {
            delete this.allocatedPorts[service];
            await this.saveConfig();
            return true;
        }
        return false;
    }

    getServicePorts() {
        // Return current configuration for all services
        const config = {};
        
        for (const service of Object.keys(this.defaultPorts)) {
            config[service] = this.allocatedPorts[service] || this.defaultPorts[service];
        }
        
        return config;
    }
}

module.exports = PortManager;