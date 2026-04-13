// /api/usage — API usage data aggregation
// Reads OpenAI and Claude CSV files from website/data/
// Returns aggregated usage metrics + budget info
// GET /api/usage?provider=openai|claude|all

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.join(__dirname, '..', 'data');

// In-memory cache
if (!globalThis.__usageCache) {
  globalThis.__usageCache = {
    openai: [],
    claude: [],
    config: {},
    cachedAt: null,
    cacheDuration: 3600000, // 1 hour
  };
}

function mtnNow() {
  return new Date().toLocaleString('sv-SE', { timeZone: 'America/Denver' }).replace(' ', 'T') + '-07:00';
}

// Parse CSV content
function parseCSV(content) {
  const lines = content.trim().split('\n');
  if (lines.length < 2) return [];

  const headers = lines[0].split(',').map(h => h.trim());
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // Simple CSV parse (handles basic cases, not quoted values with commas)
    const values = line.split(',').map(v => v.trim());
    const row = {};

    headers.forEach((header, idx) => {
      const val = values[idx] || '';
      // Try to parse as number
      if (val && !isNaN(val) && val !== '') {
        row[header] = parseFloat(val);
      } else {
        row[header] = val;
      }
    });

    rows.push(row);
  }

  return rows;
}

// Read OpenAI CSV files
function readOpenAIData() {
  try {
    const files = fs.readdirSync(dataDir)
      .filter(f => f.match(/^completions_usage.*\.csv$/))
      .map(f => path.join(dataDir, f));

    if (files.length === 0) return [];

    const results = [];

    files.forEach(file => {
      const content = fs.readFileSync(file, 'utf-8');
      const rows = parseCSV(content);

      rows.forEach(row => {
        // Skip empty rows
        if (!row.model) return;

        const data = {
          date: row.end_time_iso?.split('T')[0] || '',
          model: row.model || '',
          input_tokens: row.input_tokens || 0,
          output_tokens: row.output_tokens || 0,
          requests: row.num_model_requests || 1,
        };

        // Calculate cost
        const pricing = config.openai_pricing[data.model] || config.openai_pricing['gpt-4o'];
        if (pricing) {
          data.input_cost = (data.input_tokens / 1000) * pricing.input;
          data.output_cost = (data.output_tokens / 1000) * pricing.output;
          data.total_cost = data.input_cost + data.output_cost;
        } else {
          data.input_cost = 0;
          data.output_cost = 0;
          data.total_cost = 0;
        }

        results.push(data);
      });
    });

    return results;
  } catch (err) {
    console.error('[usage] OpenAI CSV read error:', err.message);
    return [];
  }
}

// Read Claude CSV files
function readClaudeData() {
  try {
    const files = fs.readdirSync(dataDir)
      .filter(f => f.match(/^claude_api_tokens.*\.csv$/))
      .map(f => path.join(dataDir, f));

    if (files.length === 0) return [];

    const results = [];

    files.forEach(file => {
      const content = fs.readFileSync(file, 'utf-8');
      const rows = parseCSV(content);

      rows.forEach(row => {
        // Skip empty rows
        if (!row.model_version) return;

        const inputTokens = (row.usage_input_tokens_no_cache || 0) +
                            (row.usage_input_tokens_cache_write_5m || 0) +
                            (row.usage_input_tokens_cache_write_1h || 0) +
                            (row.usage_input_tokens_cache_read || 0);
        const outputTokens = row.usage_output_tokens || 0;

        const data = {
          date: row.usage_date_utc || '',
          model: row.model_version || '',
          api_key: row.api_key || '',
          input_tokens: inputTokens,
          output_tokens: outputTokens,
          requests: 1,
        };

        // Calculate cost based on model
        let modelKey = data.model.toLowerCase();
        if (modelKey.includes('sonnet')) modelKey = 'sonnet';
        else if (modelKey.includes('haiku')) modelKey = 'haiku';

        const pricing = config.claude_pricing[modelKey] || config.claude_pricing['haiku'];
        if (pricing) {
          data.input_cost = (data.input_tokens / 1000000) * pricing.input;
          data.output_cost = (data.output_tokens / 1000000) * pricing.output;
          data.total_cost = data.input_cost + data.output_cost;
        } else {
          data.input_cost = 0;
          data.output_cost = 0;
          data.total_cost = 0;
        }

        results.push(data);
      });
    });

    return results;
  } catch (err) {
    console.error('[usage] Claude CSV read error:', err.message);
    return [];
  }
}

// Load config
function loadConfig() {
  try {
    const configPath = path.join(dataDir, 'usage-config.json');
    const content = fs.readFileSync(configPath, 'utf-8');
    return JSON.parse(content);
  } catch (err) {
    console.error('[usage] Config read error:', err.message);
    return {
      openai_budget: 100.00,
      claude_budget: 50.00,
      openai_pricing: { 'gpt-4o': { input: 2.50, output: 10.00 } },
      claude_pricing: { 'haiku': { input: 0.80, output: 4.00 } },
    };
  }
}

let config = loadConfig();

// Main handler
export default function handler(req, res) {
  const provider = req.query.provider || 'all';
  const now = new Date();
  const cache = globalThis.__usageCache;

  // Check if we need to refresh cache
  if (!cache.cachedAt || (now - cache.cachedAt) > cache.cacheDuration) {
    try {
      config = loadConfig(); // Reload config in case it changed
      cache.config = config;
      cache.openai = readOpenAIData();
      cache.claude = readClaudeData();
      cache.cachedAt = now;
    } catch (err) {
      console.error('[usage] Cache refresh error:', err.message);
    }
  }

  try {
    let openaiData = cache.openai;
    let claudeData = cache.claude;

    // Aggregate by date
    const openaiByDate = {};
    const claudeByDate = {};

    openaiData.forEach(row => {
      if (!openaiByDate[row.date]) {
        openaiByDate[row.date] = {
          date: row.date,
          model: row.model,
          input_tokens: 0,
          output_tokens: 0,
          requests: 0,
          total_cost: 0,
        };
      }
      openaiByDate[row.date].input_tokens += row.input_tokens;
      openaiByDate[row.date].output_tokens += row.output_tokens;
      openaiByDate[row.date].requests += row.requests;
      openaiByDate[row.date].total_cost += row.total_cost || 0;
    });

    claudeData.forEach(row => {
      if (!claudeByDate[row.date]) {
        claudeByDate[row.date] = {
          date: row.date,
          model: row.model,
          input_tokens: 0,
          output_tokens: 0,
          requests: 0,
          total_cost: 0,
        };
      }
      claudeByDate[row.date].input_tokens += row.input_tokens;
      claudeByDate[row.date].output_tokens += row.output_tokens;
      claudeByDate[row.date].requests += row.requests;
      claudeByDate[row.date].total_cost += row.total_cost || 0;
    });

    // Calculate totals
    const openaiTotal = Object.values(openaiByDate).reduce((acc, row) => ({
      input_tokens: acc.input_tokens + row.input_tokens,
      output_tokens: acc.output_tokens + row.output_tokens,
      requests: acc.requests + row.requests,
      total_cost: acc.total_cost + row.total_cost,
    }), { input_tokens: 0, output_tokens: 0, requests: 0, total_cost: 0 });

    const claudeTotal = Object.values(claudeByDate).reduce((acc, row) => ({
      input_tokens: acc.input_tokens + row.input_tokens,
      output_tokens: acc.output_tokens + row.output_tokens,
      requests: acc.requests + row.requests,
      total_cost: acc.total_cost + row.total_cost,
    }), { input_tokens: 0, output_tokens: 0, requests: 0, total_cost: 0 });

    // Round costs
    openaiTotal.total_cost = Math.round(openaiTotal.total_cost * 100) / 100;
    claudeTotal.total_cost = Math.round(claudeTotal.total_cost * 100) / 100;

    const response = {
      ok: true,
      updatedAt: mtnNow(),
      provider: provider,
    };

    if (provider === 'openai' || provider === 'all') {
      response.openai = {
        daily: Object.values(openaiByDate).sort((a, b) => a.date.localeCompare(b.date)),
        total: openaiTotal,
        budget: cache.config.openai_budget || 100.00,
        remaining: (cache.config.openai_budget || 100.00) - openaiTotal.total_cost,
        percentUsed: ((openaiTotal.total_cost / (cache.config.openai_budget || 100.00)) * 100).toFixed(1),
      };
    }

    if (provider === 'claude' || provider === 'all') {
      response.claude = {
        daily: Object.values(claudeByDate).sort((a, b) => a.date.localeCompare(b.date)),
        total: claudeTotal,
        budget: cache.config.claude_budget || 50.00,
        remaining: (cache.config.claude_budget || 50.00) - claudeTotal.total_cost,
        percentUsed: ((claudeTotal.total_cost / (cache.config.claude_budget || 50.00)) * 100).toFixed(1),
      };
    }

    response.config = {
      openai_budget: cache.config.openai_budget || 100.00,
      claude_budget: cache.config.claude_budget || 50.00,
    };

    return res.status(200).json(response);
  } catch (err) {
    console.error('[usage] Handler error:', err.message);
    return res.status(500).json({
      ok: false,
      error: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
    });
  }
}
