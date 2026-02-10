# Spanish Translation Tracker (Global)

Tracking Spanish translations across ALL projects for language learning.

---

## ⚠️ MANDATORY SESSION STARTUP

**This file MUST be loaded at the START of EVERY session.**

When you see reference to this file in CLAUDE.md:
1. **Immediately read this file at session start** - do NOT wait for the user to ask
2. **Apply all instructions from the first user message** - no exceptions
3. **Begin automatic tracking** - corrected + translation (mental tracking, no file writes until `/update-spanish`)

**Why this matters:** User expects consistent behavior across all sessions. Not loading this file = breaking user's standing instructions.

**Failure mode:** If you don't provide corrected + translation from the first message, you've failed to follow these instructions.

---

## Response Format (AUTOMATIC)

For **every user request**, automatically provide:

1. **Corrected version**: Make it grammatically correct while avoiding rephrasing if possible. Prefix with "Corrected:"
2. **Spanish translation**: Provide a grammatically correct Spanish translation that stays close to the original request. Prefix with "Traducción:"
3. **Track words mentally**: Remember new words/phrases for later logging (DO NOT write to file automatically - prevents visual noise)
4. **Natural Spanish**: Occasionally add simple Spanish sentences/phrases in conversations naturally

**Important:** To reduce visual noise, DO NOT update the log file automatically. Words are tracked mentally and dumped to the log only when user calls `/update-spanish`.

**Example:**
```
User: "Explain potential reuse sstate-cache and downloads. Will either these two be reused?"

Response:
Corrected: "Explain the potential for reusing sstate-cache and downloads. Will either of these two be reused?"
Traducción: "Explica el potencial de reutilizar sstate-cache y downloads. ¿Se reutilizará alguno de estos dos?"
```

### Natural Spanish Integration

Add simple Spanish sentences throughout conversations when appropriate:
- Success confirmations: "¡Perfecto!", "¡Excelente!", "¡Muy bien!"
- Transitions: "Ahora..." (Now...), "Entonces..." (So...)
- Questions: "¿Listo?" (Ready?), "¿Entiendes?" (Understand?)
- Encouragement: "¡Vamos!" (Let's go!), "¡Adelante!" (Go ahead!)
- Common phrases: "Por supuesto" (Of course), "Claro que sí" (Of course yes)

Keep it simple, natural, and contextual. Include English translation in parentheses when helpful.

## Commands

### View Tracked Words
Ask: "Show me my Spanish translations" or "Print Spanish word list"

### Dump Tracked Words to Log
Use: **`/update-spanish`**

Batch writes all accumulated translations from the current session to the log file.

This command will:
1. Review all translations provided in current session
2. Extract new vocabulary not yet in the log
3. Update `spanish-translations-log.md` with all new entries at once
4. Update statistics and timestamp
5. Report count of words added

## Translation Log

**Log File:** `spanish-translations-log.md` (same directory)

The actual translation log with all tracked words, phrases, and frequency counts is maintained in a separate file that is **excluded from git** (personal learning data).

To view your translations, read the log file:
```bash
cat ~/.claude/memory/spanish-translations-log.md
```

Or simply ask Claude to show your translation stats.

---
*Location: ~/.claude/memory/spanish-translations.md (GLOBAL - synced across machines via git)*
*Log Location: ~/.claude/memory/spanish-translations-log.md (LOCAL - not in git)*
