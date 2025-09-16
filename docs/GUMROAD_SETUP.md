# Gumroad Setup Instructions

Follow these steps to start selling FreshBooks MCP:

## Step 1: Create Your Gumroad Account
1. Go to https://gumroad.com
2. Click "Start Selling" 
3. Sign up with your email

## Step 2: Create Your Products

### Product 1: FreshBooks MCP Pro - Monthly
1. Click "New Product" → "Digital Product"
2. **Name:** FreshBooks MCP Pro - Monthly Subscription
3. **Price:** $9.99
4. **Type:** Subscription (Monthly)
5. **File:** Upload the MSI installer from `releases/FreshBooksMCP-Setup-1.0.0.msi`
6. **Cover Image:** Use the logo from assets folder
7. **Description:** Copy this:
   ```
   AI-powered FreshBooks integration for Claude Desktop
   
   ✅ Natural language control
   ✅ 95% accurate categorization  
   ✅ Automated bank reconciliation
   ✅ Anomaly detection
   ✅ Financial insights
   ✅ Priority support
   
   Works with Claude Desktop to give you AI superpowers for FreshBooks.
   ```

8. **License Keys:** 
   - Enable "Generate a unique license key per sale"
   - Format: FBMCP-XXXX-XXXX-XXXX

9. **Email Receipt:** Add this custom text:
   ```
   Thank you for purchasing FreshBooks MCP Pro!
   
   YOUR LICENSE KEY: {license_key}
   
   ACTIVATION INSTRUCTIONS:
   1. Download and install FreshBooks MCP
   2. Open the application
   3. Go to Settings → License
   4. Enter your license key
   5. Restart the application
   
   Your Pro features are now active!
   
   Need help? Email support@ehrigconsulting.com
   ```

10. Click "Save" and then "Publish"
11. **Copy your product URL** (looks like: https://gumroad.com/l/fbmcp-monthly)

### Product 2: FreshBooks MCP Pro - Yearly
1. Repeat the above steps but:
   - **Name:** FreshBooks MCP Pro - Yearly Subscription
   - **Price:** $79.99
   - **Type:** Subscription (Yearly)
   - Everything else the same
2. **Copy your product URL** (looks like: https://gumroad.com/l/fbmcp-yearly)

## Step 3: Update Your Website

Edit `docs/index.html` and find this function (around line 440):
```javascript
function subscribe(plan) {
```

Replace it with your actual Gumroad URLs:
```javascript
function subscribe(plan) {
    // Replace these with your actual Gumroad URLs
    if (plan === 'monthly') {
        window.location.href = 'YOUR_MONTHLY_GUMROAD_URL';
    } else {
        window.location.href = 'YOUR_YEARLY_GUMROAD_URL';  
    }
}
```

## Step 4: Test Everything

1. Visit your Gumroad product pages
2. Make sure they look good
3. Do a test purchase (Gumroad has test mode)
4. Verify you receive the license key email

## Step 5: You're Live! 🎉

Your website will be at:
https://samurabuddha.github.io/freshbooks-mcp-public

Share this link to start selling!

## Gumroad Dashboard

Monitor your sales at:
https://gumroad.com/dashboard

## Tips:
- Start with these prices, you can always increase later
- Gumroad handles all taxes and compliance
- They pay out weekly via direct deposit
- Use their affiliate program to get others to promote (they handle that too!)

That's it! You're now selling FreshBooks MCP!