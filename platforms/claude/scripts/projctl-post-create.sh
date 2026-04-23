#!/usr/bin/env bash
# Post-hook for `projctl create`: creates status.md and reminds about issue tracking.

input=$(cat)
output=$(echo "$input" | jq -r '.tool_response.output // ""')

context=""

# --- status.md creation for new milestones ---
if echo "$output" | grep -q "Created milestone"; then
  while IFS= read -r line; do
    milestone_num=$(echo "$line" | grep -oP 'Created milestone %\K[0-9]+')
    milestone_title=$(echo "$line" | grep -oP 'Created milestone %[0-9]+: \K.+')
    [ -z "$milestone_num" ] && continue

    # Collect epic IDs from the same output
    epic_ids=$(echo "$output" | grep -oP 'Created epic &\K[0-9]+' | tr '\n' ' ' | xargs)

    # Find matching planning directory
    if [ -d "planning" ]; then
      plan_dir=$(find planning -maxdepth 3 -type d -name "milestone-${milestone_num}-*" 2>/dev/null | head -1)
      if [ -n "$plan_dir" ] && [ ! -f "$plan_dir/status.md" ]; then
        # Build epics frontmatter
        if [ -n "$epic_ids" ]; then
          epics_yaml="  epics:"
          for eid in $epic_ids; do
            epics_yaml="${epics_yaml}"$'\n'"    - ${eid}"
          done
        else
          epics_yaml="  epic: # fill in epic ID"
        fi

        cat > "$plan_dir/status.md" <<EOF
---
sync:
  milestone: ${milestone_num}
${epics_yaml}
---

# Milestone ${milestone_num}: ${milestone_title}

**Milestone ID:** %${milestone_num}
**Status:** Not started ⬜

## Issues

(No issues yet)

## Dependency Order

TBD

## Design Documents

TBD
EOF
        context="${context}Created ${plan_dir}/status.md for milestone %${milestone_num}.\n"
      fi
    fi
  done < <(echo "$output" | grep "Created milestone")
fi

# --- reminder for new issues ---
if echo "$output" | grep -q "Created Issues" && echo "$output" | grep -q "work_items/"; then
  context="${context}projctl create completed — update the relevant planning/status.md with the new issue number(s) shown above."
fi

# Emit context if anything happened
if [ -n "$context" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
    "$(echo -e "$context" | sed 's/"/\\"/g' | tr '\n' ' ')"
fi
