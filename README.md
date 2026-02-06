# Clawdsense

A CLI tool for searching across all your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions locally. Parses JSONL session transcripts, indexes them into [Typesense](https://typesense.org/), and provides fast keyword and semantic search from the command line.

**Primary use cases:**

- "Find the session where I worked on X"
- "What did I change and why?"
- "Which sessions touched this file?"

## How It Works

Claude Code stores every session as a `.jsonl` file under `~/.claude/projects/`. Clawdsense parses these transcripts, extracts each conversation turn (your prompt + Claude's response), and indexes them into Typesense with metadata like git branch, tools used, and files modified.

Each turn is indexed as a separate searchable document with session metadata denormalized onto it. This means search results point you to the **exact turn** in a conversation, not just the session.

### Search Modes

- **Hybrid** (default) — combines keyword matching with semantic vector search, so you can find relevant turns even when you don't remember the exact wording
- **Keyword** — traditional full-text search across prompts and assistant responses
- **Semantic** — pure vector similarity search using Typesense's built-in `ts/all-MiniLM-L12-v2` embedding model (runs locally, no API calls)

## Requirements

- Ruby >= 3.1
- [Typesense](https://typesense.org/docs/guide/install-typesense.html) v28+ (local instance)

### Installing Typesense (macOS)

```bash
brew install typesense-server@30.1
brew services start typesense-server@30.1
```

The default config uses `localhost:8108` with API key `xyz`.

## Installation

```bash
git clone https://github.com/jeremysmithco/clawdsense.git
cd clawdsense
bundle install
```

## Usage

### Index your sessions

```bash
# Index all sessions across all projects
clawdsense index

# Index a specific project
clawdsense index --project my-rails-app

# Force re-index everything (ignore cache)
clawdsense index --force
```

Indexing is incremental by default — unchanged sessions are skipped based on file size.

### Search

```bash
# Hybrid search (keyword + semantic, the default)
clawdsense search "pagination refactor"

# Keyword-only search
clawdsense search --keyword "ActiveRecord validation"

# Semantic search (find conceptually similar turns)
clawdsense search --semantic "fixing a date boundary bug"

# Filter by project, branch, or file
clawdsense search "user notifications" --project my-rails-app
clawdsense search "user notifications" --branch feature/notifications
clawdsense search --file "notifications_controller.rb"
```

Search results show matching turns grouped by session. When a match comes from Claude's response rather than your prompt, a highlight snippet shows where the match occurred:

```
--- cheerful-dancing-otter a1b2c3d4-5678-9abc-def0-1234567890ab
 Pagination Refactor & System Tests
 2026-01-23 09:46  branch: feature/pagination  model: claude-opus-4-5-20251101

 Turn 6: "Okay, this is looking good, but I see another possible issue..."
   -> Tools: Edit, Read, Bash  Files: posts_controller_test.rb
 Turn 3: "On the second test for the paginated list, I don't like the sleep..."
   => ...returns the correct page when offset exceeds total count...
   -> Tools: Grep, Read, Edit  Files: posts_controller_test.rb
```

### View a session

```bash
# Show the full conversation for a session (supports short ID prefixes)
clawdsense show a1b2c3d4
```

### Resume a session

```bash
# cd to the original working directory and resume with Claude Code
clawdsense resume a1b2c3d4
```

### List recent sessions

```bash
clawdsense sessions
clawdsense sessions --project my-rails-app
```

### Stats

```bash
clawdsense stats
```

## What Gets Indexed

**Per turn:**
- Your prompt (primary search field)
- Claude's response text (secondary search field)
- Claude's thinking/reasoning (keyword searchable, excluded from embeddings)
- Tools used (e.g. `Edit`, `Bash`, `Grep`)
- Files modified and files read
- Bash commands executed
- Git branch at time of turn
- Duration

**Per session (denormalized onto each turn):**
- Session ID, project, slug, summary
- Working directory, model, Claude Code version
- File size (used for incremental indexing)

## Configuration

By default, Clawdsense connects to Typesense at `localhost:8108` with API key `xyz`. Override with an environment variable:

```bash
export TYPESENSE_API_KEY=your-api-key
```

## Project Structure

```
clawdsense/
├── Gemfile
├── clawdsense.gemspec
├── bin/
│   └── clawdsense          # CLI entry point
└── lib/
    ├── clawdsense.rb        # Top-level require, version
    └── clawdsense/
        ├── cli.rb           # Command parsing (optparse)
        ├── config.rb        # Typesense connection, collection schema
        ├── formatter.rb     # Terminal output formatting
        ├── indexer.rb       # Scan, parse, batch upsert
        ├── parser.rb        # JSONL transcript parsing
        └── search.rb        # Typesense query builder
```

## Development

```bash
# Run directly from source
bundle exec ruby -Ilib bin/clawdsense search "your query"

# Or install as a gem locally
gem build clawdsense.gemspec && gem install clawdsense-0.1.0.gem
clawdsense search "your query"
```

## License

MIT
