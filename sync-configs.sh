#!/usr/bin/env bash
# Two-way sync for GenAI platform configurations
# Usage: ./sync-configs.sh [sync|install] [--dry-run] [--claude] [--codex]

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory (repository root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
MODE="sync"  # sync (home → repo) or install (repo → home)
DRY_RUN=false
SYNC_CLAUDE=true
SYNC_CODEX=true
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        sync|install)
            MODE=$1
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --claude)
            SYNC_CODEX=false
            shift
            ;;
        --codex)
            SYNC_CLAUDE=false
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [MODE] [OPTIONS]

Two-way sync for GenAI platform configurations

MODES:
  sync         Backup configurations from home directory to repository (default)
               ~/.claude → platforms/claude/
               ~/.codex → platforms/codex/

  install      Restore configurations from repository to home directory
               platforms/claude/ → ~/.claude
               platforms/codex/ → ~/.codex

OPTIONS:
  --dry-run    Show what would be synced without making changes
  --force, -f  Skip confirmation prompts (use with caution in install mode)
  --claude     Only process Claude configurations
  --codex      Only process Codex configurations
  -h, --help   Show this help message

EXAMPLES:
  $0 sync                    # Backup all configs
  $0 sync --dry-run          # Preview backup changes
  $0 install --claude        # Restore Claude config only
  $0 install --dry-run       # Preview restore changes
  $0 install --force         # Restore without confirmation (dangerous!)

EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored status messages
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to confirm installation
confirm_install() {
    local platform=$1
    local dest_dir=$2

    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    print_status "$YELLOW" "WARNING: This will overwrite files in: $dest_dir"
    echo -n "Continue? [y/N] "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            print_status "$YELLOW" "Skipping ${platform}"
            return 1
            ;;
    esac
}

# Function to sync a platform configuration
# Usage: sync_platform PLATFORM HOME_DIR REPO_DIR INCLUDES[@] [EXCLUDES[@]]
sync_platform() {
    local platform=$1
    local home_dir=$2
    local repo_dir=$3
    shift 3

    # Parse includes and excludes
    local includes=()
    local excludes=()
    local parsing_includes=true

    for arg in "$@"; do
        if [[ "$arg" == "--excludes" ]]; then
            parsing_includes=false
            continue
        fi

        if [[ "$parsing_includes" == true ]]; then
            includes+=("$arg")
        else
            excludes+=("$arg")
        fi
    done

    # Determine source and destination based on mode
    local source_dir dest_dir action
    if [[ "$MODE" == "sync" ]]; then
        source_dir="$home_dir"
        dest_dir="$repo_dir"
        action="Backing up"
    else
        source_dir="$repo_dir"
        dest_dir="$home_dir"
        action="Installing"
    fi

    print_status "$BLUE" "==> ${action} ${platform}..."

    # Check if source directory exists
    if [[ ! -d "$source_dir" ]]; then
        print_status "$YELLOW" "Warning: Source directory not found: $source_dir"
        return 1
    fi

    # Confirm installation if in install mode
    if [[ "$MODE" == "install" ]] && [[ "$DRY_RUN" == false ]]; then
        if ! confirm_install "$platform" "$dest_dir"; then
            return 1
        fi
    fi

    # Create destination directory if it doesn't exist
    if [[ ! -d "$dest_dir" ]]; then
        print_status "$YELLOW" "Creating destination directory: $dest_dir"
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$dest_dir"
        fi
    fi

    # Build rsync command
    local rsync_cmd=(rsync -av --delete)

    # Add dry-run flag if enabled
    if [[ "$DRY_RUN" == true ]]; then
        rsync_cmd+=(--dry-run)
    fi

    # Add exclude patterns FIRST (rsync uses first match)
    for pattern in "${excludes[@]}"; do
        rsync_cmd+=(--exclude="$pattern")
    done

    # Add include patterns
    for pattern in "${includes[@]}"; do
        rsync_cmd+=(--include="$pattern")
    done

    # Exclude everything else
    rsync_cmd+=(--exclude='*')

    # Add source and destination
    rsync_cmd+=("$source_dir/" "$dest_dir/")

    # Execute rsync
    if "${rsync_cmd[@]}"; then
        print_status "$GREEN" "✓ ${platform} ${action,,} complete"
        return 0
    else
        print_status "$RED" "✗ ${platform} ${action,,} failed"
        return 1
    fi
}

# Main execution
main() {
    local title
    if [[ "$MODE" == "sync" ]]; then
        title="GenAI Configuration Backup (Home → Repo)"
    else
        title="GenAI Configuration Install (Repo → Home)"
    fi

    print_status "$BLUE" "========================================"
    print_status "$BLUE" "$title"
    print_status "$BLUE" "========================================"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        print_status "$YELLOW" "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    if [[ "$MODE" == "install" ]] && [[ "$FORCE" == false ]] && [[ "$DRY_RUN" == false ]]; then
        print_status "$YELLOW" "Install mode will overwrite files in your home directory"
        print_status "$YELLOW" "You will be prompted before each platform"
        echo ""
    fi

    local exit_code=0

    # Process Claude configurations
    if [[ "$SYNC_CLAUDE" == true ]]; then
        # Include patterns for Claude
        local claude_includes=(
            'CLAUDE.md'
            'agents/'
            'agents/**'
            'commands/'
            'commands/**'
            'skills/'
            'skills/**'
        )

        if ! sync_platform "Claude" \
            "$HOME/.claude" \
            "$SCRIPT_DIR/platforms/claude" \
            "${claude_includes[@]}"; then
            exit_code=1
        fi
        echo ""
    fi

    # Process Codex configurations
    if [[ "$SYNC_CODEX" == true ]]; then
        # Include patterns for Codex
        local codex_includes=(
            '*.md'
            'agents/'
            'agents/**'
            'commands/'
            'commands/**'
            'skills/'
            'skills/**'
        )

        # Exclude .system directories (built-in Codex skills)
        local codex_excludes=(
            'skills/.system'
        )

        if ! sync_platform "Codex" \
            "$HOME/.codex" \
            "$SCRIPT_DIR/platforms/codex" \
            "${codex_includes[@]}" \
            --excludes \
            "${codex_excludes[@]}"; then
            exit_code=1
        fi
        echo ""
    fi

    # Show git status (only for sync mode)
    if [[ "$MODE" == "sync" ]] && [[ "$DRY_RUN" == false ]]; then
        print_status "$BLUE" "==> Git status:"
        cd "$SCRIPT_DIR"
        if git status --short platforms/; then
            echo ""
            print_status "$GREEN" "Backup complete! Review changes and commit if needed."
        fi
    elif [[ "$MODE" == "install" ]] && [[ "$DRY_RUN" == false ]]; then
        print_status "$GREEN" "Installation complete!"
    fi

    return $exit_code
}

# Run main function
main "$@"
