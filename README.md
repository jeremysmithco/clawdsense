# Clawdsense

A CLI tool for searching across all your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions locally. Parses JSONL session transcripts, indexes them into [Typesense](https://typesense.org/), and provides fast keyword search from the command line.

## How It Works

Claude Code stores every session as a `.jsonl` file under `~/.claude/projects/`. Clawdsense parses these transcripts and indexes each message — every user prompt and every assistant response — as its own document in Typesense.

## Requirements

- Ruby >= 3.1
- [Typesense](https://typesense.org/docs/guide/install-typesense.html) v30+ (local instance)

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

# Force re-index everything (ignore the mtime cache)
clawdsense index --force
```

Indexing is incremental by default — unchanged sessions are skipped based on file mtime.

### Search

```bash
clawdsense search "pagination refactor"

# Filter by project — matches any segment of the working directory path
clawdsense search "user notifications" --project my-rails-app
```

### Resume a session

```bash
# cd to the original working directory and resume with Claude Code
clawdsense resume <session-id>
```

## Configuration

By default, Clawdsense connects to Typesense at `localhost:8108` with API key `xyz`. Override with an environment variable:

```bash
export TYPESENSE_API_KEY=your-api-key
```

## License

MIT
