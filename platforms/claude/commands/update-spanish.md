---
name: update-spanish
description: Dump accumulated Spanish translations to log file
---

# Update Spanish Log Command

Batch update the Spanish translation log with all translations from the current session.

**Purpose:** To reduce visual noise, translations are tracked mentally but NOT written to file automatically. This command dumps all accumulated words at once.

## Actions

1. Review recent conversation history (last 5-10 exchanges)

2. Identify any user messages that:
   - Received a "Corrected:" and "Traducción:" response
   - But were NOT logged to `~/.claude/memory/spanish-translations-log.md`

3. Extract new vocabulary:
   - Find all Spanish words from the translations
   - Compare against existing log entries
   - Identify words not yet tracked

4. Update the log file:
   - Add new session section if needed (current date)
   - Add numbered entries for each new word with:
     - Spanish word/phrase
     - English translation
     - Example usage from the conversation
     - Count: 1 (or increment if already exists)
   - Update statistics (total unique words count)
   - Update "Last updated" timestamp

5. Report results:
   - "✓ Added [N] new words to Spanish log"
   - List the words that were added
   - Show updated total count

## Example Output

```
✓ Added 5 new words to Spanish log:

- parece (it seems/looks like)
- problemas (problems)
- agrega/agregar (add/to add)
- nuevo (new)
- comando (command)

Total vocabulary: 61 words
```

## Notes

- This command should only be needed when automatic tracking fails
- Always preserve existing log structure and numbering
- Increment counts for words that already exist
- Keep the session organized by date
