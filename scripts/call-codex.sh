#!/bin/bash
# Call Codex CLI with a prompt (fully automated, with session persistence)
# Usage: call-codex.sh "prompt text" [project_dir]
#
# Features:
# - Maintains Codex session context per project
# - Auto-retry on rate limit with exponential backoff
# - Sets markers for workflow enforcement hooks
# - Tracks review status for deployment gates
# - **Chunked sending** - splits large prompts to avoid rate limits
# - **Local caching** - caches results by content hash
#
# State is stored in project directory: <project>/.ai-collab/

set -euo pipefail

PROMPT="$1"
PROJECT_DIR="${2:-$PWD}"
MAX_RETRIES=5
RETRY_DELAY=60  # seconds
CHUNK_SIZE=3000  # characters per chunk (conservative for token limit)

# Find project with ai-collab session (search up from PROJECT_DIR)
find_session() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.ai-collab" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  echo "$1"
}

PROJECT_DIR=$(find_session "$PROJECT_DIR")
SESSION_DIR="$PROJECT_DIR/.ai-collab"
CODEX_SESSION_FILE="$SESSION_DIR/codex-session-id"
CODEX_WRITING_MARKER="$SESSION_DIR/.codex-writing"
REVIEW_PASSED_MARKER="$SESSION_DIR/codex-review-passed"
PLAN_APPROVED_MARKER="$SESSION_DIR/plan-approved"
CACHE_DIR="$SESSION_DIR/cache"

if [ -z "$PROMPT" ]; then
    echo "Usage: call-codex.sh 'prompt' [project_dir]"
    exit 1
fi

# Ensure directories exist
mkdir -p "$SESSION_DIR"
mkdir -p "$CACHE_DIR"

# Add .ai-collab to .gitignore if not present
GITIGNORE="$PROJECT_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
    if ! grep -q "^\.ai-collab" "$GITIGNORE"; then
        echo ".ai-collab/" >> "$GITIGNORE"
        echo "📝 Added .ai-collab/ to .gitignore" >&2
    fi
elif [[ -d "$PROJECT_DIR/.git" ]]; then
    echo ".ai-collab/" > "$GITIGNORE"
    echo "📝 Created .gitignore with .ai-collab/" >&2
fi

# Ensure project directory is a git repo (Codex requirement)
if [ ! -d "$PROJECT_DIR/.git" ]; then
    git -C "$PROJECT_DIR" init >/dev/null 2>&1
fi

# Set marker indicating Codex is writing
touch "$CODEX_WRITING_MARKER"

cleanup() {
    rm -f "$CODEX_WRITING_MARKER"
}
trap cleanup EXIT

# ============================================================
# FEATURE 1: Local Cache - avoid resending identical content
# ============================================================
compute_hash() {
    echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

check_cache() {
    local hash="$1"
    local cache_file="$CACHE_DIR/$hash"
    if [[ -f "$cache_file" ]]; then
        # Check if cache is fresh (less than 24 hours old)
        local cache_age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $cache_age -lt 86400 ]]; then
            echo "💾 Cache hit (hash: ${hash:0:8}...)" >&2
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

save_cache() {
    local hash="$1"
    local content="$2"
    echo "$content" > "$CACHE_DIR/$hash"
    echo "💾 Cached result (hash: ${hash:0:8}...)" >&2
}

# Check cache first
PROMPT_HASH=$(compute_hash "$PROMPT")
if cached_result=$(check_cache "$PROMPT_HASH"); then
    echo "$cached_result"
    exit 0
fi

# ============================================================
# FEATURE 2: Chunked Sending - split large prompts
# ============================================================
send_to_codex() {
    local prompt="$1"
    local existing_session="$2"

    if [[ -n "$existing_session" ]]; then
        echo "$prompt" | codex exec resume "$existing_session" \
            --dangerously-bypass-approvals-and-sandbox \
            --skip-git-repo-check \
            --json \
            2>&1
    else
        echo "$prompt" | codex exec \
            --dangerously-bypass-approvals-and-sandbox \
            --skip-git-repo-check \
            --json \
            2>&1
    fi
}

extract_response() {
    local raw="$1"
    local output=""

    # Try jq extraction first
    output=$(echo "$raw" | grep '"type":"item.completed"' | grep '"type":"agent_message"' | \
        jq -r '.item.text' 2>/dev/null | tr '\n' ' ' || echo "")

    # Fallback to simpler approach
    if [[ -z "$output" ]]; then
        output=$(echo "$raw" | grep -o '"text":"[^"]*"' | grep -v "reasoning" | tail -1 | cut -d'"' -f4 || echo "")
    fi

    # Last resort: return raw
    if [[ -z "$output" ]]; then
        output="$raw"
    fi

    echo "$output"
}

# Check if we have an existing Codex session
EXISTING_SESSION=""
if [[ -f "$CODEX_SESSION_FILE" ]]; then
    EXISTING_SESSION=$(cat "$CODEX_SESSION_FILE")
    echo "🔄 Resuming Codex session: ${EXISTING_SESSION:0:8}..." >&2
fi

cd "$PROJECT_DIR"

# Determine if we need chunked sending
PROMPT_LENGTH=${#PROMPT}
if [[ $PROMPT_LENGTH -gt $CHUNK_SIZE ]]; then
    echo "📦 Large prompt detected (${PROMPT_LENGTH} chars), using chunked sending..." >&2

    # Split into: instruction + content chunks
    # Extract instruction (first line or first 500 chars before content)
    INSTRUCTION=$(echo "$PROMPT" | head -c 500 | head -1)
    CONTENT=$(echo "$PROMPT" | tail -c +$((${#INSTRUCTION} + 1)))

    # Send instruction first to establish context
    echo "📤 Sending instruction..." >&2
    raw_output=$(send_to_codex "I'm going to send you a document in parts for review. Please wait until I say 'END OF DOCUMENT' before responding. Here's the instruction: $INSTRUCTION" "$EXISTING_SESSION")

    # Extract session ID if new
    if [[ -z "$EXISTING_SESSION" ]]; then
        NEW_SESSION_ID=$(echo "$raw_output" | grep -o '"thread_id":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "$NEW_SESSION_ID" ]]; then
            echo "$NEW_SESSION_ID" > "$CODEX_SESSION_FILE"
            EXISTING_SESSION="$NEW_SESSION_ID"
            echo "✨ New Codex session: ${NEW_SESSION_ID:0:8}..." >&2
        fi
    fi

    # Send content in chunks
    CHUNK_NUM=1
    TOTAL_CHUNKS=$(( (${#CONTENT} + CHUNK_SIZE - 1) / CHUNK_SIZE ))

    while [[ ${#CONTENT} -gt 0 ]]; do
        CHUNK="${CONTENT:0:$CHUNK_SIZE}"
        CONTENT="${CONTENT:$CHUNK_SIZE}"

        echo "📤 Sending chunk $CHUNK_NUM/$TOTAL_CHUNKS..." >&2

        if [[ ${#CONTENT} -eq 0 ]]; then
            # Last chunk - ask for response
            raw_output=$(send_to_codex "PART $CHUNK_NUM (FINAL):
$CHUNK

END OF DOCUMENT. Please review the complete document and respond." "$EXISTING_SESSION")
        else
            # More chunks coming - just acknowledge
            send_to_codex "PART $CHUNK_NUM:
$CHUNK

(More parts coming, please wait...)" "$EXISTING_SESSION" >/dev/null 2>&1
            sleep 2  # Small delay between chunks to avoid rate limit
        fi

        CHUNK_NUM=$((CHUNK_NUM + 1))
    done

    output=$(extract_response "$raw_output")
else
    # Normal single-request flow with retry
    for i in $(seq 1 $MAX_RETRIES); do
        raw_output=$(send_to_codex "$PROMPT" "$EXISTING_SESSION")

        # Check for rate limit error
        if echo "$raw_output" | grep -qi "rate.limit\|too.many.requests\|quota\|429"; then
            error_msg=$(echo "$raw_output" | grep -oiE "(rate.limit[^\"]*|too.many.requests[^\"]*|quota[^\"]*|429[^\"]*)" | head -1)
            echo "⏳ Rate limited. Waiting ${RETRY_DELAY}s... (attempt $i/$MAX_RETRIES)" >&2
            echo "   Error: ${error_msg:-unknown rate limit error}" >&2
            echo "$(date -Iseconds) - Rate limit: $error_msg" >> "$SESSION_DIR/rate-limit.log"
            sleep $RETRY_DELAY
            RETRY_DELAY=$((RETRY_DELAY * 2))
            continue
        fi

        # Check for session not found error
        if echo "$raw_output" | grep -qi "session.*not.*found\|invalid.*session\|unknown.*session"; then
            echo "⚠️ Session expired, creating new session..." >&2
            rm -f "$CODEX_SESSION_FILE"
            EXISTING_SESSION=""
            raw_output=$(send_to_codex "$PROMPT" "")
        fi

        # Extract and save session ID if new
        if [[ -z "$EXISTING_SESSION" ]]; then
            NEW_SESSION_ID=$(echo "$raw_output" | grep -o '"thread_id":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ -n "$NEW_SESSION_ID" ]]; then
                echo "$NEW_SESSION_ID" > "$CODEX_SESSION_FILE"
                echo "✨ New Codex session: ${NEW_SESSION_ID:0:8}..." >&2
            fi
        fi

        output=$(extract_response "$raw_output")
        break
    done
fi

# Check if output is empty (all retries failed)
if [[ -z "${output:-}" ]]; then
    echo "❌ Failed after $MAX_RETRIES retries" >&2
    exit 1
fi

# Success - check if this was a review that passed
if echo "$output" | grep -qiE "(no objections|looks good|lgtm|approved|no issues|code is correct|well.written)"; then
    if echo "$PROMPT" | grep -qiE "(review.*plan|plan.*review)"; then
        echo "✅ Codex PLAN review passed" >&2
        touch "$PLAN_APPROVED_MARKER"
        echo "$(date -Iseconds) - Plan approved" >> "$SESSION_DIR/review-history.log"
    elif echo "$PROMPT" | grep -qiE "(review.*code|code.*review|review these|review this)"; then
        echo "✅ Codex CODE review passed" >&2
        touch "$REVIEW_PASSED_MARKER"
        echo "$(date -Iseconds) - Code review passed" >> "$SESSION_DIR/review-history.log"
    elif echo "$PROMPT" | grep -qi "review"; then
        echo "✅ Codex review passed" >&2
        touch "$PLAN_APPROVED_MARKER"
        touch "$REVIEW_PASSED_MARKER"
        echo "$(date -Iseconds) - Review passed (generic)" >> "$SESSION_DIR/review-history.log"
    fi
fi

# Save to cache
save_cache "$PROMPT_HASH" "$output"

echo "$output"
exit 0
