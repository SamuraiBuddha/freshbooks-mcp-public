// Local AI Engine for FreshBooks MCP
// Bundled with installer for offline AI capabilities

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs').promises;
const http = require('http');

class LocalAIEngine {
    constructor() {
        this.vllmProcess = null;
        this.modelPath = path.join(process.env.ProgramFiles, 'FreshBooksMCP', 'models');
        this.vllmPort = 8000;
        this.ollamaPort = 11434;
        this.currentBackend = null;
        
        // Models bundled with installer
        this.bundledModels = {
            // Quantized models for efficiency (GGUF format)
            'phi-3-mini': {
                file: 'phi-3-mini-4k-instruct-q4.gguf',
                size: '2.3GB',
                backend: 'llama.cpp',
                purpose: 'Transaction categorization',
                ramRequired: '4GB'
            },
            'tinyllama-finance': {
                file: 'tinyllama-1.1b-finance-q4.gguf', 
                size: '638MB',
                backend: 'llama.cpp',
                purpose: 'Quick categorization',
                ramRequired: '2GB'
            },
            'nomic-embed': {
                file: 'nomic-embed-text-v1.5-q4.gguf',
                size: '276MB',
                backend: 'llama.cpp',
                purpose: 'Text embeddings',
                ramRequired: '1GB'
            }
        };
    }

    async initialize() {
        // Check available backends
        const backend = await this.detectBestBackend();
        
        if (backend === 'vllm' && await this.hasGPU()) {
            return this.initializeVLLM();
        } else if (backend === 'ollama' && await this.isOllamaInstalled()) {
            return this.initializeOllama();
        } else {
            // Fallback to CPU-based llama.cpp
            return this.initializeLlamaCpp();
        }
    }

    async detectBestBackend() {
        // Priority order: vLLM (GPU) > Ollama > llama.cpp (CPU)
        
        if (await this.hasGPU()) {
            const vram = await this.getGPUMemory();
            if (vram >= 4000) { // 4GB+ VRAM
                return 'vllm';
            }
        }
        
        if (await this.isOllamaInstalled()) {
            return 'ollama';
        }
        
        return 'llama.cpp'; // Always available as bundled fallback
    }

    async hasGPU() {
        try {
            const { exec } = require('child_process').promises;
            await exec('nvidia-smi');
            return true;
        } catch {
            return false;
        }
    }

    async getGPUMemory() {
        try {
            const { exec } = require('child_process').promises;
            const { stdout } = await exec('nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits');
            return parseInt(stdout.trim());
        } catch {
            return 0;
        }
    }

    async isOllamaInstalled() {
        try {
            const response = await this.makeRequest('GET', 'localhost', this.ollamaPort, '/');
            return response.includes('Ollama');
        } catch {
            return false;
        }
    }

    async initializeVLLM() {
        console.log('Initializing vLLM with GPU acceleration...');
        
        // Start vLLM server with quantized model
        this.vllmProcess = spawn('python', [
            '-m', 'vllm.entrypoints.openai.api_server',
            '--model', path.join(this.modelPath, 'microsoft', 'phi-3-mini-4k-instruct'),
            '--port', this.vllmPort.toString(),
            '--gpu-memory-utilization', '0.8',
            '--max-model-len', '4096',
            '--dtype', 'float16',
            '--quantization', 'awq' // Activation-aware Weight Quantization
        ], {
            cwd: this.modelPath,
            env: { ...process.env, CUDA_VISIBLE_DEVICES: '0' }
        });

        this.currentBackend = 'vllm';
        await this.waitForServer(this.vllmPort);
        console.log('vLLM server ready on port', this.vllmPort);
    }

    async initializeOllama() {
        console.log('Using existing Ollama installation...');
        
        // Pull required models if not present
        const models = ['phi3:mini', 'nomic-embed-text'];
        for (const model of models) {
            await this.pullOllamaModel(model);
        }
        
        this.currentBackend = 'ollama';
    }

    async initializeLlamaCpp() {
        console.log('Initializing bundled llama.cpp backend...');
        
        const serverPath = path.join(process.env.ProgramFiles, 'FreshBooksMCP', 'bin', 'server.exe');
        const modelFile = path.join(this.modelPath, this.bundledModels['tinyllama-finance'].file);
        
        // Start llama.cpp server
        this.vllmProcess = spawn(serverPath, [
            '--model', modelFile,
            '--port', this.vllmPort.toString(),
            '--n-gpu-layers', '0', // CPU only for compatibility
            '--ctx-size', '4096',
            '--threads', '4'
        ]);

        this.currentBackend = 'llama.cpp';
        await this.waitForServer(this.vllmPort);
        console.log('llama.cpp server ready on port', this.vllmPort);
    }

    async categorizeTransaction(description, amount, vendor = '') {
        const prompt = `Categorize this business expense:
Amount: $${amount}
Description: ${description}
Vendor: ${vendor}

Categories: Office Supplies, Software, Travel, Meals, Equipment, Marketing, Professional Services, Utilities, Rent, Insurance, Contractor, Other

Return JSON only:
{
  "category": "selected_category",
  "confidence": 0.95,
  "tax_deductible": true,
  "business_percentage": 100
}`;

        const response = await this.complete(prompt);
        try {
            return JSON.parse(response);
        } catch {
            // Fallback to rule-based categorization
            return this.ruleBasedCategorization(description, vendor);
        }
    }

    async detectAnomaly(transaction, history) {
        // Generate embeddings for similarity comparison
        const currentEmbed = await this.generateEmbedding(JSON.stringify(transaction));
        
        // Compare with historical patterns
        let maxSimilarity = 0;
        for (const historical of history) {
            const histEmbed = await this.generateEmbedding(JSON.stringify(historical));
            const similarity = this.cosineSimilarity(currentEmbed, histEmbed);
            maxSimilarity = Math.max(maxSimilarity, similarity);
        }
        
        // Low similarity = potential anomaly
        return {
            isAnomaly: maxSimilarity < 0.7,
            confidence: 1 - maxSimilarity,
            reason: maxSimilarity < 0.7 ? 'Unusual pattern detected' : 'Normal transaction'
        };
    }

    async complete(prompt) {
        if (this.currentBackend === 'vllm' || this.currentBackend === 'llama.cpp') {
            return this.completionViaOpenAI(prompt);
        } else if (this.currentBackend === 'ollama') {
            return this.completionViaOllama(prompt);
        } else {
            throw new Error('No AI backend available');
        }
    }

    async completionViaOpenAI(prompt) {
        const data = JSON.stringify({
            model: 'model',
            prompt: prompt,
            max_tokens: 500,
            temperature: 0.3
        });

        const response = await this.makeRequest('POST', 'localhost', this.vllmPort, '/v1/completions', data);
        const result = JSON.parse(response);
        return result.choices[0].text;
    }

    async completionViaOllama(prompt) {
        const data = JSON.stringify({
            model: 'phi3:mini',
            prompt: prompt,
            stream: false
        });

        const response = await this.makeRequest('POST', 'localhost', this.ollamaPort, '/api/generate', data);
        const result = JSON.parse(response);
        return result.response;
    }

    async generateEmbedding(text) {
        if (this.currentBackend === 'ollama') {
            const data = JSON.stringify({
                model: 'nomic-embed-text',
                prompt: text
            });
            
            const response = await this.makeRequest('POST', 'localhost', this.ollamaPort, '/api/embeddings', data);
            const result = JSON.parse(response);
            return result.embedding;
        } else {
            // Use bundled nomic-embed via llama.cpp
            const data = JSON.stringify({
                input: text
            });
            
            const response = await this.makeRequest('POST', 'localhost', this.vllmPort, '/v1/embeddings', data);
            const result = JSON.parse(response);
            return result.data[0].embedding;
        }
    }

    ruleBasedCategorization(description, vendor) {
        // Fallback rules when AI is unavailable
        const rules = {
            'Office Supplies': /office|supplies|paper|pen|stapl/i,
            'Software': /software|subscription|saas|license|app/i,
            'Travel': /hotel|flight|uber|lyft|taxi|airfare/i,
            'Meals': /restaurant|lunch|dinner|coffee|food/i,
            'Equipment': /computer|laptop|monitor|printer|hardware/i,
            'Marketing': /advertis|marketing|ad|campaign|social media/i,
            'Professional Services': /consulting|legal|accounting|professional/i,
            'Utilities': /electric|gas|water|internet|phone/i,
            'Rent': /rent|lease|office space/i,
            'Insurance': /insurance|liability|coverage/i,
            'Contractor': /contractor|freelance|consultant|1099/i
        };

        const combined = `${description} ${vendor}`.toLowerCase();
        
        for (const [category, pattern] of Object.entries(rules)) {
            if (pattern.test(combined)) {
                return {
                    category,
                    confidence: 0.8,
                    tax_deductible: true,
                    business_percentage: 100
                };
            }
        }

        return {
            category: 'Other',
            confidence: 0.5,
            tax_deductible: true,
            business_percentage: 100
        };
    }

    cosineSimilarity(vec1, vec2) {
        let dotProduct = 0;
        let norm1 = 0;
        let norm2 = 0;
        
        for (let i = 0; i < vec1.length; i++) {
            dotProduct += vec1[i] * vec2[i];
            norm1 += vec1[i] * vec1[i];
            norm2 += vec2[i] * vec2[i];
        }
        
        return dotProduct / (Math.sqrt(norm1) * Math.sqrt(norm2));
    }

    async waitForServer(port, maxAttempts = 30) {
        for (let i = 0; i < maxAttempts; i++) {
            try {
                await this.makeRequest('GET', 'localhost', port, '/health');
                return true;
            } catch {
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }
        throw new Error(`Server failed to start on port ${port}`);
    }

    makeRequest(method, host, port, path, data = null) {
        return new Promise((resolve, reject) => {
            const options = {
                hostname: host,
                port: port,
                path: path,
                method: method,
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': data ? Buffer.byteLength(data) : 0
                }
            };

            const req = http.request(options, (res) => {
                let body = '';
                res.on('data', chunk => body += chunk);
                res.on('end', () => resolve(body));
            });

            req.on('error', reject);
            if (data) req.write(data);
            req.end();
        });
    }

    async pullOllamaModel(model) {
        console.log(`Pulling Ollama model: ${model}`);
        const { exec } = require('child_process').promises;
        await exec(`ollama pull ${model}`);
    }

    async shutdown() {
        if (this.vllmProcess) {
            this.vllmProcess.kill();
            this.vllmProcess = null;
        }
    }
}

module.exports = LocalAIEngine;