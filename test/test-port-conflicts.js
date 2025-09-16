// Test Port Conflict Resolution
// Demonstrates automatic port allocation when conflicts occur

const LocalAIEngine = require('../src/ai/local-ai-engine');
const PortManager = require('../src/ai/port-manager');

async function testPortConflictResolution() {
    console.log('=== FreshBooks MCP Port Conflict Resolution Test ===\n');
    
    // Create port manager instance
    const portManager = new PortManager();
    await portManager.initialize();
    
    // Check current port status
    console.log('1. Checking port availability...\n');
    const status = await portManager.getPortsStatus();
    
    console.log('Available ports:');
    for (const [service, port] of Object.entries(status.available)) {
        console.log(`  ✅ ${service}: ${port}`);
    }
    
    console.log('\nOccupied ports:');
    for (const [service, info] of Object.entries(status.occupied)) {
        console.log(`  ❌ ${service}: ${info.port} (occupied by ${info.occupiedBy})`);
    }
    
    // Detect conflicts
    console.log('\n2. Detecting port conflicts...\n');
    const conflicts = await portManager.detectConflicts();
    
    if (conflicts.length === 0) {
        console.log('No port conflicts detected! All default ports are available.');
    } else {
        console.log(`Found ${conflicts.length} port conflict(s):`);
        for (const conflict of conflicts) {
            console.log(`  - ${conflict.service}: port ${conflict.port} occupied by ${conflict.occupiedBy}`);
        }
    }
    
    // Get suggestions for resolution
    console.log('\n3. Generating port suggestions...\n');
    const suggestions = await portManager.suggestPortConfiguration();
    
    if (Object.keys(suggestions).length > 0) {
        console.log('Recommended port configuration:');
        for (const [service, suggestion] of Object.entries(suggestions)) {
            console.log(`  ${service}:`);
            console.log(`    Current: ${suggestion.currentDefault} (${suggestion.occupiedBy})`);
            console.log(`    Suggested: ${suggestion.suggestedPort}`);
        }
    } else {
        console.log('No port changes needed - all services can use default ports.');
    }
    
    // Allocate ports for services
    console.log('\n4. Allocating ports for AI services...\n');
    
    const services = ['vllm', 'ollama', 'lmstudio', 'llamacpp'];
    const allocations = {};
    
    for (const service of services) {
        try {
            const port = await portManager.allocatePort(service);
            allocations[service] = port;
            console.log(`  ✅ ${service}: allocated port ${port}`);
        } catch (error) {
            console.log(`  ❌ ${service}: failed to allocate port - ${error.message}`);
        }
    }
    
    // Show final configuration
    console.log('\n5. Final port configuration:\n');
    const finalConfig = portManager.getServicePorts();
    
    console.log('Service ports:');
    for (const [service, port] of Object.entries(finalConfig)) {
        console.log(`  ${service}: http://localhost:${port}`);
    }
    
    // Test with AI Engine
    console.log('\n6. Testing with LocalAIEngine...\n');
    
    const aiEngine = new LocalAIEngine();
    
    try {
        // This will automatically handle port conflicts
        await aiEngine.resolvePortConflicts();
        
        console.log('\n✅ Port conflict resolution successful!');
        console.log('\nThe AI engine will automatically allocate available ports when initialized.');
        
    } catch (error) {
        console.log(`\n❌ Error: ${error.message}`);
    }
    
    console.log('\n=== Test Complete ===');
}

// Run the test
testPortConflictResolution().catch(console.error);