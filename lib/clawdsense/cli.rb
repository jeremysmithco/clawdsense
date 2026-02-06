# frozen_string_literal: true

require "optparse"

module Clawdsense
  class CLI
    COMMANDS = %w[index search show sessions stats].freeze

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @options = {}
    end

    def run
      command = @argv.shift

      case command
      when "index"   then cmd_index
      when "search"  then cmd_search
      when "show"    then cmd_show
      when "resume"  then cmd_resume
      when "sessions" then cmd_sessions
      when "stats"   then cmd_stats
      when "-v", "--version"
        puts "clawdsense #{VERSION}"
      when "-h", "--help", nil
        print_help
      else
        $stderr.puts "Unknown command: #{command}"
        print_help
        exit 1
      end
    end

    private

    def cmd_index
      parse_options do |opts|
        opts.banner = "Usage: clawdsense index [options]"
        opts.on("--project PROJECT", "Index only this project") { |v| @options[:project] = v }
        opts.on("--force", "Re-index all sessions (ignore cache)") { @options[:force] = true }
      end

      indexer = Indexer.new(project: @options[:project], force: @options[:force])
      indexer.run
    end

    def cmd_search
      parse_options do |opts|
        opts.banner = "Usage: clawdsense search [options] QUERY"
        opts.on("--semantic", "Semantic search only") { @options[:mode] = :semantic }
        opts.on("--keyword", "Keyword search only") { @options[:mode] = :keyword }
        opts.on("--project PROJECT", "Filter by project") { |v| @options[:project] = v }
        opts.on("--branch BRANCH", "Filter by git branch") { |v| @options[:branch] = v }
        opts.on("--file FILE", "Filter by modified file path") { |v| @options[:file] = v }
        opts.on("--session SESSION", "Search within a specific session") { |v| @options[:session] = v }
        opts.on("--per-page N", Integer, "Results per page (default 10)") { |v| @options[:per_page] = v }
      end

      query = @argv.join(" ")
      if query.empty?
        $stderr.puts "Error: search query required"
        exit 1
      end

      search = Search.new
      mode = @options[:mode] || :hybrid
      result = search.send(mode, query,
        project: @options[:project],
        branch: @options[:branch],
        file: @options[:file],
        session_id: @options[:session],
        per_page: @options[:per_page] || 10
      )

      puts Formatter.new.format_search_results(result)
    end

    def cmd_show
      session_id = @argv.shift
      if session_id.nil? || session_id.empty?
        $stderr.puts "Error: session ID or prefix required"
        $stderr.puts "Usage: clawdsense show SESSION_ID"
        exit 1
      end

      result = Search.new.session_turns(session_id)
      if result["error"]
        $stderr.puts result["error"]
        exit 1
      end
      puts Formatter.new.format_session_detail(result)
    end

    def cmd_resume
      session_id = @argv.shift
      if session_id.nil? || session_id.empty?
        $stderr.puts "Error: session ID or prefix required"
        $stderr.puts "Usage: clawdsense resume SESSION_ID"
        exit 1
      end

      search = Search.new
      result = search.session_turns(session_id)
      if result["error"]
        $stderr.puts result["error"]
        exit 1
      end

      hits = result["hits"] || []
      if hits.empty?
        $stderr.puts "No turns found for session '#{session_id}'"
        exit 1
      end

      doc = hits.first["document"]
      full_id = doc["session_id"]
      cwd = doc["cwd"]

      unless cwd && Dir.exist?(cwd)
        $stderr.puts "Working directory no longer exists: #{cwd}"
        exit 1
      end

      puts "Resuming session #{full_id}"
      puts "  dir: #{cwd}"
      Dir.chdir(cwd)
      exec("claude", "--resume", full_id)
    end

    def cmd_sessions
      parse_options do |opts|
        opts.banner = "Usage: clawdsense sessions [options]"
        opts.on("--project PROJECT", "Filter by project") { |v| @options[:project] = v }
        opts.on("--per-page N", Integer, "Number of sessions (default 20)") { |v| @options[:per_page] = v }
      end

      result = Search.new.list_sessions(
        project: @options[:project],
        per_page: @options[:per_page] || 20
      )
      puts Formatter.new.format_session_list(result)
    end

    def cmd_stats
      result = Search.new.stats
      puts Formatter.new.format_stats(result)
    end

    def parse_options
      parser = OptionParser.new do |opts|
        yield opts
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit
        end
      end
      parser.parse!(@argv)
    end

    def print_help
      puts <<~HELP
        clawdsense #{VERSION} — Search across your Claude Code sessions

        Usage: clawdsense COMMAND [options]

        Commands:
          index      Index session transcripts into Typesense
          search     Search across indexed sessions
          show       Show a specific session's conversation
          resume     Resume a session in its original working directory
          sessions   List recent sessions
          stats      Show collection statistics

        Options:
          -v, --version    Show version
          -h, --help       Show help

        Run 'clawdsense COMMAND --help' for command-specific options.
      HELP
    end
  end
end
