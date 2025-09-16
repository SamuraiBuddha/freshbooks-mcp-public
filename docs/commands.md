# FreshBooks MCP - Complete Command Reference

## 🎯 Feature Tiers
- 🆓 **Trial**: Available in free 30-day trial (read-only + limited writes)
- 💎 **Pro**: Requires Pro subscription ($9.99/mo or $79.99/yr)
- 🏢 **Enterprise**: Custom pricing for multi-company support

## 📋 Table of Contents
- [Client Management](#client-management)
- [Invoicing](#invoicing)
- [Estimates](#estimates)
- [Expenses](#expenses)
- [Payments](#payments)
- [Reports](#reports)
- [Time Tracking](#time-tracking)
- [Projects](#projects)
- [Services & Items](#services--items)
- [Advanced Features](#advanced-features)

## Client Management

### read_clients 🆓
**Tier:** Trial  
**Description:** List all clients with optional filtering  
**Parameters:**
- `active_only` (boolean, optional): Show only active clients (default: true)

**Example:**
```
"Show me all my clients"
"List inactive clients"
"Find clients in Florida"
```

### write_client 💎
**Tier:** Pro  
**Description:** Create or update a client  
**Parameters:**
- `organization` (string, required): Company name
- `fname` (string, optional): First name
- `lname` (string, optional): Last name
- `email` (string, optional): Email address
- `phone` (string, optional): Phone number

**Example:**
```
"Add Acme Corp as a new client with email contact@acme.com"
"Update Phillips & Jordan phone to 407-555-1234"
```

## Invoicing

### read_invoices 🆓
**Tier:** Trial  
**Description:** List all invoices with optional status filtering  
**Parameters:**
- `status` (string, optional): Filter by status
  - Options: draft, sent, viewed, paid, overdue, partial, disputed

**Example:**
```
"Show me unpaid invoices"
"List overdue invoices"
"Find all draft invoices"
```

### write_invoice 🆓/💎
**Tier:** Trial (5/month) | Pro (unlimited)  
**Description:** Create a new invoice  
**Parameters:**
- `client_id` (integer, required): Client ID
- `amount` (number, required): Invoice amount
- `description` (string, optional): Invoice description
- `due_days` (integer, optional): Days until due (default: 30)

**Example:**
```
"Create a $5000 invoice for client 12345"
"Generate invoice for BIM modeling services, $2500, due in 15 days"
```

## Estimates

### read_estimates 🆓
**Tier:** Trial  
**Description:** List all estimates  
**Parameters:** None

**Example:**
```
"Show all estimates"
"List pending estimates"
"Find accepted estimates not yet invoiced"
```

### write_estimate 💎
**Tier:** Pro  
**Description:** Create a new estimate  
**Parameters:**
- `client_id` (integer, required): Client ID
- `amount` (number, required): Estimate amount
- `description` (string, optional): Estimate description
- `valid_days` (integer, optional): Days valid (default: 30)

**Example:**
```
"Create $10,000 estimate for Hensel Phelps"
"Generate estimate for clash detection services, $3500"
```

## Expenses

### read_expenses 🆓
**Tier:** Trial  
**Description:** List all expenses with date filtering  
**Parameters:**
- `date_from` (date, optional): Start date (format: YYYY-MM-DD)
- `date_to` (date, optional): End date (format: YYYY-MM-DD)

**Example:**
```
"Show expenses for January 2024"
"List all expenses from 2024-01-01 to 2024-12-31"
"What did I spend last quarter?"
```

### write_expense 🆓/💎
**Tier:** Trial (10/month) | Pro (unlimited)  
**Description:** Create a new expense  
**Parameters:**
- `amount` (number, required): Expense amount
- `vendor` (string, required): Vendor name
- `category_id` (integer, optional): Category ID
- `date` (date, optional): Expense date
- `notes` (string, optional): Additional notes

**Example:**
```
"Add $47.50 office supplies expense from Staples"
"Record $1200 contractor payment to John Doe"
```

## Payments

### read_payments 🆓
**Tier:** Trial  
**Description:** List all payments  
**Parameters:** None

**Example:**
```
"Show all payments received"
"List payments this month"
```

### write_payment 💎
**Tier:** Pro  
**Description:** Record a payment  
**Parameters:**
- `invoice_id` (integer, required): Invoice ID
- `amount` (number, required): Payment amount
- `date` (date, optional): Payment date
- `payment_type` (string, optional): Type (default: Cash)
- `note` (string, optional): Payment note

**Example:**
```
"Record $5000 payment for invoice 1234"
"Log ACH payment of $2500 received today"
```

## Reports

### read_reports 🆓
**Tier:** Trial (basic) | Pro (advanced)  
**Description:** Get financial reports  
**Parameters:**
- `report_type` (string, optional): Type of report
  - Options: profitloss, balancesheet, cashflow
- `start_date` (date, optional): Report start date
- `end_date` (date, optional): Report end date

**Example:**
```
"Show profit and loss for 2024"
"Generate Q1 2024 financial report"
"What's my cash flow this month?"
```

## Time Tracking

### read_time_entries 🆓
**Tier:** Trial  
**Description:** List all time entries  
**Parameters:** None

**Example:**
```
"Show my time entries"
"List hours logged this week"
```

### write_time_entry 💎
**Tier:** Pro  
**Description:** Create a time entry  
**Parameters:**
- `client_id` (integer, required): Client ID
- `duration_seconds` (integer, required): Duration in seconds
- `started_at` (string, optional): Start time
- `note` (string, optional): Description

**Example:**
```
"Log 3 hours for client 12345"
"Track 90 minutes of BIM modeling work"
```

## Projects

### read_projects 🆓
**Tier:** Trial  
**Description:** List all projects  
**Parameters:** None

**Example:**
```
"Show all projects"
"List active projects"
```

### write_project 💎
**Tier:** Pro  
**Description:** Create a new project  
**Parameters:**
- `title` (string, required): Project title
- `client_id` (integer, required): Client ID
- `description` (string, optional): Project description

**Example:**
```
"Create Airport BIM project for Hensel Phelps"
"Start new project: MEP Coordination"
```

## Services & Items

### read_items 🆓
**Tier:** Trial  
**Description:** List all services/items  
**Parameters:** None

**Example:**
```
"Show my service catalog"
"List all billable items"
"What are my hourly rates?"
```

### write_item 💎
**Tier:** Pro  
**Description:** Create a new billable item  
**Parameters:**
- `name` (string, required): Item name
- `unit_cost` (number, required): Price/rate
- `description` (string, optional): Item description
- `qty` (integer, optional): Quantity (default: 1)

**Example:**
```
"Add BIM Modeling service at $150/hour"
"Create Clash Detection service for $125/hour"
```

## Advanced Features

### Categories

#### read_categories 🆓
**Tier:** Trial  
**Description:** List expense categories  
**Example:** `"Show expense categories"`

#### write_category 💎
**Tier:** Pro  
**Description:** Create expense category  
**Parameters:**
- `name` (string, required): Category name
- `parent_id` (integer, optional): Parent category
- `is_cogs` (boolean, optional): Cost of goods sold

### Taxes

#### read_taxes 🆓
**Tier:** Trial  
**Description:** List all taxes  
**Example:** `"Show tax configurations"`

#### write_tax 💎
**Tier:** Pro  
**Description:** Create a new tax  
**Parameters:**
- `name` (string, required): Tax name
- `tax_number` (string, required): Tax number
- `amount` (number, required): Tax rate

### Recurring Invoices

#### read_recurring 💎
**Tier:** Pro  
**Description:** List recurring invoice profiles  
**Example:** `"Show recurring invoices"`

#### write_recurring 💎
**Tier:** Pro  
**Description:** Create recurring invoice profile  
**Parameters:**
- `client_id` (integer, required): Client ID
- `frequency` (string, required): Frequency
- `amount` (number, required): Amount

### Credit Notes

#### read_credit_notes 💎
**Tier:** Pro  
**Description:** List credit notes  
**Example:** `"Show credit notes"`

#### write_credit_note 💎
**Tier:** Pro  
**Description:** Create credit note  
**Parameters:**
- `client_id` (integer, required): Client ID
- `amount` (number, required): Credit amount
- `notes` (string, optional): Notes

### Staff Management

#### read_staff 💎
**Tier:** Pro  
**Description:** List staff members  
**Example:** `"Show team members"`

#### write_staff 💎
**Tier:** Pro  
**Description:** Create staff member  
**Parameters:**
- `email` (string, required): Email address
- `fname` (string, optional): First name
- `lname` (string, optional): Last name
- `role` (string, optional): Role

## Usage Tips

1. **Natural Language**: Commands can be expressed naturally - Claude will interpret your intent
2. **Chaining**: Combine multiple commands in one request for complex workflows
3. **Filtering**: Most read commands support filtering - just describe what you want
4. **Dates**: Use natural language like "last month" or specific dates like "2024-01-15"
5. **Context**: Claude remembers previous commands in the conversation for follow-ups

## Error Handling

If a command fails, you'll receive:
- Clear error message explaining what went wrong
- Suggested fixes or alternative commands
- Required vs optional parameters clarification

## Rate Limits

### 🆓 Trial Tier
- **100 API calls per day** across all operations
- **5 invoices/month** creation limit
- **10 expenses/month** creation limit
- **Read-only** for advanced features
- **30-day** trial period

### 💎 Pro Tier
- **Unlimited API calls**
- **Unlimited write operations**
- **All advanced features** enabled
- **Bulk operations** with automatic throttling
- **Priority support** (4-hour response)

### 🏢 Enterprise
- **Custom rate limits** based on needs
- **Multi-company support**
- **Dedicated infrastructure**
- **SLA guarantees**