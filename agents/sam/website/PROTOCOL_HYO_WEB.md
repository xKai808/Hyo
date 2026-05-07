# PROTOCOL_HYO_WEB.md — hyo.world HTML Page Protocol
**Version:** 1.0 · **Owner:** Sam · **Read before touching any hyo.world HTML**

This protocol defines everything needed to create or edit pages on hyo.world with consistent, reproducible results. Read it fully before writing a single line of HTML.

---

## 1. File Structure & Dual-Path Rule

Every HTML file exists in TWO locations — both must always be kept in sync:

```
agents/sam/website/<page>.html   ← canonical source (edit here)
website/<page>.html              ← Vercel deploy path (mirror here)
```

**After every edit:**
```bash
cp agents/sam/website/<page>.html website/<page>.html
```

Never edit only one path. Vercel reads from `website/`. The canonical source lives in `agents/sam/website/`. Drift between them causes silent production bugs.

---

## 2. Fonts

Always include exactly these Google Fonts — no substitutions:

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=Inter:wght@300;400;500;600&family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet" />
```

| Variable     | Family       | Use                              |
|-------------|-------------|----------------------------------|
| `--font-d`  | Syne        | Display — headings, brand names  |
| `--font-b`  | Inter       | Body — paragraphs, UI text       |
| `--font-m`  | DM Mono     | Mono — labels, tags, toggles     |

---

## 3. Theme System (Bright / Dark)

### 3.1 CSS Variables — Full Set

Always define both `:root` (dark default) and `:root[data-theme="bright"]` overrides:

```css
:root {
  --bg:           #0a0a12;
  --bg-deep:      #050509;
  --bg-card:      #0f0f1a;
  --fg:           #f2e2c4;
  --muted:        rgba(242, 226, 196, 0.50);
  --dim:          rgba(242, 226, 196, 0.28);
  --border:       rgba(242, 226, 196, 0.12);
  --accent:       #e8b877;
  --accent-bright:#f6c98a;
  --accent-dim:   rgba(232, 184, 119, 0.08);
  --accent-line:  rgba(232, 184, 119, 0.30);
  --ok:           #a3c98a;
  --err:          #e89070;
  --font-d:       'Syne', sans-serif;
  --font-b:       'Inter', sans-serif;
  --font-m:       'DM Mono', monospace;
  --ease:         cubic-bezier(0.16, 1, 0.3, 1);
}

:root[data-theme="bright"] {
  --bg:           #f8f4ee;
  --bg-deep:      #ede8df;
  --bg-card:      #ffffff;
  --fg:           #1c160f;
  --muted:        rgba(28, 22, 15, 0.55);
  --dim:          rgba(28, 22, 15, 0.35);
  --border:       rgba(28, 22, 15, 0.12);
  --accent:       #b8741a;
  --accent-bright:#c8841e;
  --accent-dim:   rgba(184, 116, 26, 0.09);
  --accent-line:  rgba(184, 116, 26, 0.28);
  --ok:           #3a7a28;
  --err:          #b84030;
}
```

For pages without `--font-*` vars (index, explore, dashboard), also define:
```css
/* explore / dashboard / index use these additional vars */
--card:     #ffffff;          /* bright */  /  --card: #0f0f1a;      /* dark */
--gold:     #c9a96e;          /* bright */  /  --gold: #e8b877;      /* dark */
--shadow:   rgba(26,26,46,0.09); /* bright */ / --shadow: rgba(0,0,0,0.35); /* dark */
--mast-bg:  rgba(244,241,235,0.92); /* bright */ / rgba(8,8,16,0.88); /* dark */
```

### 3.2 HTML Tag — Always Hardcode Bright

```html
<html lang="en" data-theme="bright">
```

**Never** leave `<html>` without `data-theme`. Without it, the dark `:root` renders before JS fires → dark flash on load.

### 3.3 Theme Toggle Button — Standard Pattern

```html
<button class="theme-toggle" id="themeToggle" title="Toggle light/dark">☾</button>
```

CSS (use `.theme-toggle` for content pages, `.theme-toggle-btn` for index):
```css
.theme-toggle {
  background: none; border: 1px solid var(--border); border-radius: 100px;
  color: var(--dim); cursor: pointer; font-size: 13px; padding: 4px 10px;
  font-family: var(--font-m); letter-spacing: 0.08em;
  transition: color 0.2s, border-color 0.2s;
}
.theme-toggle:hover { color: var(--fg); border-color: var(--accent-line); }
```

JS — always this exact pattern, localStorage key always `hyo_theme`:
```js
function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  localStorage.setItem('hyo_theme', t);
  const btn = document.getElementById('themeToggle');
  if (btn) btn.textContent = t === 'bright' ? '☾' : '☀';
}
function toggleTheme() {
  const cur = document.documentElement.getAttribute('data-theme') || 'bright';
  applyTheme(cur === 'dark' ? 'bright' : 'dark');
}
document.getElementById('themeToggle').addEventListener('click', function(e) {
  e.stopPropagation();
  toggleTheme();
});
applyTheme(localStorage.getItem('hyo_theme') || 'bright');
```

**Rules:**
- localStorage key is always `hyo_theme` — never `aurora-theme`, `hyo_dt`, or anything else
- Default fallback is always `'bright'`
- Always `e.stopPropagation()` on the toggle button click
- Never use `onclick=` on large div areas — use `addEventListener` with `e.target.closest()` guards

---

## 4. Mast Bar (Top Navigation)

Every page uses the same fixed mast bar pattern:

```html
<nav class="mast">
  <a href="/" class="logo">HYO</a>
  <div style="display:flex; align-items:center; gap:16px;">
    <!-- page-specific nav items -->
    <button class="theme-toggle" id="themeToggle" title="Toggle light/dark">☾</button>
  </div>
</nav>
```

```css
.mast {
  position: fixed; top: 0; left: 0; right: 0; z-index: 50;
  display: flex; align-items: center; justify-content: space-between;
  padding: 20px 32px;
  font-family: var(--font-m); font-size: 11px;
  letter-spacing: 0.14em; text-transform: uppercase; color: var(--dim);
  background: var(--mast-bg, transparent);
  backdrop-filter: blur(12px);
}
.mast a { color: var(--dim); text-decoration: none; }
.mast a:hover { color: var(--fg); }
.mast .logo { color: var(--accent); font-family: var(--font-d); font-weight: 700; letter-spacing: 0.06em; }
```

---

## 5. Cards

```css
/* Standard content card */
.card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  transition: border-color 0.25s var(--ease), box-shadow 0.25s var(--ease);
}
.card:hover {
  border-color: var(--accent-line);
  box-shadow: 0 4px 18px var(--shadow, rgba(0,0,0,0.07));
}
```

**Hard rule: never hardcode a card background color.** Always `var(--bg-card)`. Never `#fff`, `#0f0f1a`, or any hex directly on a card that must adapt to theme.

The only exception: an element that is intentionally always dark or always light regardless of theme — scope it with `:root[data-theme="bright"] .element { }` overrides and document why.

---

## 6. Typography Scale

```css
/* Display / hero */
font-family: var(--font-d); font-weight: 800; font-size: clamp(42px, 6vw, 82px);

/* Section heading */
font-family: var(--font-d); font-weight: 600; font-size: clamp(22px, 2.6vw, 32px);

/* Body */
font-family: var(--font-b); font-size: 15px; line-height: 1.7; color: var(--muted);

/* Label / eyebrow */
font-family: var(--font-m); font-size: 10px; letter-spacing: 0.22em; text-transform: uppercase; color: var(--accent);

/* Small label */
font-family: var(--font-m); font-size: 9px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--dim);
```

---

## 7. Buttons

```css
/* Primary CTA */
.btn-primary {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 14px 28px; border-radius: 8px;
  background: var(--accent); color: #fff;
  font-family: var(--font-m); font-size: 12px; font-weight: 500;
  letter-spacing: 0.14em; text-transform: uppercase;
  border: none; cursor: pointer;
  transition: opacity 0.2s, transform 0.2s;
}
.btn-primary:hover { opacity: 0.88; transform: translateY(-1px); }

/* Ghost / secondary */
.btn-ghost {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 13px 26px; border-radius: 8px;
  background: transparent; color: var(--accent);
  border: 1px solid var(--accent-line);
  font-family: var(--font-m); font-size: 11px;
  letter-spacing: 0.18em; text-transform: uppercase;
  cursor: pointer; transition: background 0.2s, border-color 0.2s;
}
.btn-ghost:hover { background: var(--accent-dim); border-color: var(--accent); }
```

---

## 8. Grid Background (Explore / Dashboard style)

```css
body::before {
  content: ''; position: fixed; inset: 0; pointer-events: none; z-index: 0;
  background-image:
    linear-gradient(var(--grid) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid) 1px, transparent 1px);
  background-size: 44px 44px;
}
```

Where `--grid` is defined per theme:
- Bright: `rgba(26,26,46,0.04)`
- Dark: `rgba(232,213,183,0.03)`

---

## 9. Product Copy & Pricing

Current canonical values — always use these, never invent:

| Item              | Value                    |
|------------------|--------------------------|
| Free trial       | **5-day free trial**     |
| Price            | **$19/mo**               |
| Trial CTA        | "Start my 5-day trial"   |
| Footer note      | "5-day free trial, then $19/mo · cancel anytime · we never sell your data" |
| Success message  | "No charge until day 6." |

---

## 10. Footer / Legal Line

Every page uses this footer pattern:

```html
<footer class="foot">
  <a href="/">Hyo</a> product &middot; 5-day free trial, then $19/mo &middot; cancel anytime &middot; we never sell your data
</footer>
```

```css
.foot {
  position: fixed; bottom: 0; left: 0; right: 0;
  text-align: center; padding: 16px;
  font-family: var(--font-m); font-size: 10px;
  letter-spacing: 0.1em; color: var(--dim);
}
.foot a { color: var(--dim); text-decoration: none; }
.foot a:hover { color: var(--fg); }
```

---

## 11. Common Anti-Patterns — Never Do These

| ❌ Wrong | ✅ Right |
|---------|---------|
| Hardcoded `background: #fff` on a themed element | `background: var(--bg-card)` |
| Hardcoded `color: rgba(255,255,255,0.5)` outside a dark-scoped block | `color: var(--muted)` |
| `onclick="location.href='...'` on a large div | JS `addEventListener` with `e.target.closest()` guard |
| `localStorage.setItem('aurora-theme', ...)` | Always `hyo_theme` |
| `|| 'light'` fallback | Always `|| 'bright'` |
| `[data-theme="light"]` selector | Always `[data-theme="bright"]` |
| Editing only `agents/sam/website/` | Always mirror to `website/` |
| Declaring done without verifying live URL | Fetch live + screenshot, always |

---

## 12. Deployment & Verification Checklist

Every change, no matter how small, follows this sequence:

```
1. Edit agents/sam/website/<page>.html
2. cp agents/sam/website/<page>.html website/<page>.html
3. Queue git commit:
   {
     "command": "rm -f ~/Documents/Projects/Hyo/.git/index.lock && cd ~/Documents/Projects/Hyo && git add agents/sam/website/<page>.html website/<page>.html && git commit -m '<message>' && git push origin main"
   }
4. Confirm worker.log shows exit=0
5. Wait ~30s for Vercel deploy
6. Fetch https://www.hyo.world/<page> and grep for the changed string
7. Take a browser screenshot and visually confirm
8. Check BOTH bright and dark modes for the changed element
```

**Never declare done until step 8 is complete.**

---

## 13. Page Inventory

| Page | URL | File | Purpose |
|------|-----|------|---------|
| Landing | `hyo.world/` | `index.html` | Human / Agent split entry |
| Explore | `hyo.world/explore` | `explore.html` | Agent catalog |
| Dashboard | `hyo.world/dashboard` | `dashboard.html` | Personal HQ |
| Aurora | `hyo.world/aurora` | `aurora.html` | Aurora signup flow |
| Aurora Success | `hyo.world/aurora-success` | `aurora-success.html` | Post-signup confirmation |
| Register | `hyo.world/register` | `register.html` | Agent registration |
| HQ | `hyo.world/hq` | `hq.html` | Internal HQ feed |

---

## 14. Session Start Checklist

Before creating or editing any hyo.world page:

- [ ] Read this protocol fully
- [ ] Check which pages already exist (see inventory above)
- [ ] Read the target file before editing
- [ ] Confirm design tokens match section 3 exactly
- [ ] Plan all elements using CSS variables — zero hardcoded colors

After every change:

- [ ] Mirrored to `website/` path
- [ ] Committed and pushed via queue (exit=0 confirmed)
- [ ] Live URL fetched and verified
- [ ] Screenshot taken in bright mode
- [ ] Screenshot taken in dark mode
