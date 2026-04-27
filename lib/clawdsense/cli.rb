# frozen_string_literal: true

require "optparse"

module Clawdsense
  class CLI
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
      when "index"  then cmd_index
      when "search" then cmd_search
      when "resume" then cmd_resume
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
        opts.on("--force", "Re-index all sessions (ignore cache)") { @options[:force] = true }
      end

      Indexer.new(force: @options[:force]).run
    end

    def cmd_search
      parse_options do |opts|
        opts.banner = "Usage: clawdsense search [options] QUERY"
        opts.on("--project PROJECT", "Filter by project") { |v| @options[:project] = v }
      end

      query = @argv.join(" ")
      if query.empty?
        $stderr.puts "Error: search query required"
        exit 1
      end

      result = Search.new.search(query, project: @options[:project])

      output = Formatter.new.format_search_results(result)
      if $stdout.tty?
        IO.popen(ENV.fetch("PAGER", "less -RFX"), "w") { |io| io.puts output }
      else
        puts output
      end
    rescue Errno::EPIPE
      # User quit the pager early
    end

    def cmd_resume
      session_id = @argv.shift
      if session_id.nil? || session_id.empty?
        $stderr.puts "Error: session ID required"
        $stderr.puts "Usage: clawdsense resume SESSION_ID"
        exit 1
      end

      cwd = Search.new.session_cwd(session_id)
      unless cwd
        $stderr.puts "No session found matching '#{session_id}'"
        exit 1
      end

      unless Dir.exist?(cwd)
        $stderr.puts "Working directory no longer exists: #{cwd}"
        exit 1
      end

      puts "Resuming session #{session_id}"
      puts "  dir: #{cwd}"
      Dir.chdir(cwd)
      exec("claude", "--resume", session_id)
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
          resume     Resume a session in its original working directory

        Options:
          -v, --version    Show version
          -h, --help       Show help

        Run 'clawdsense COMMAND --help' for command-specific options.
      HELP
    end
  end
end
