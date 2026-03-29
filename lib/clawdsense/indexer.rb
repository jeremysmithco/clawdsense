# frozen_string_literal: true

module Clawdsense
  class Indexer
    BATCH_SIZE = 40

    def initialize(force: false)
      @force = force
      @client = Config.client
      @collection = Config.ensure_collection!
      @stats = {sessions: 0, entries: 0, skipped: 0, errors: 0}
    end

    def run
      files = session_files
      puts "Found #{files.size} session files"

      files.each do |file|
        index_file(file)
      end

      puts "\nDone. Indexed #{@stats[:sessions]} sessions (#{@stats[:entries]} entries), " \
           "skipped #{@stats[:skipped]}, errors #{@stats[:errors]}"
      @stats
    end

    private

    def session_files
      Dir.glob(File.join(Config.projects_dir, "*", "*.jsonl")).sort
    end

    def index_file(file)
      session_id = File.basename(file, ".jsonl")
      file_mtime = File.mtime(file).to_i

      unless @force
        if already_indexed?(session_id, file_mtime)
          @stats[:skipped] += 1
          return
        end
      end

      parser = Parser.new(file)
      docs = parser.documents

      if docs.empty?
        @stats[:skipped] += 1
        return
      end

      delete_session(session_id)

      docs.each_slice(BATCH_SIZE) do |batch|
        results = @client.collections[Config::COLLECTION_NAME].documents.import(batch, action: :upsert)
        errors = results.select { |r| r["success"] == false }
        if errors.any?
          $stderr.puts "  Errors in #{session_id}: #{errors.first(3).map { |e| e["error"] }.join(", ")}"
          @stats[:errors] += errors.size
        end
      end

      @stats[:sessions] += 1
      @stats[:entries] += docs.size
      puts "#{Formatter::DIM}#{session_id} — #{docs.size} entries#{Formatter::RESET}"
    rescue => e
      $stderr.puts "  Error processing #{file}: #{e.message}"
      @stats[:errors] += 1
    end

    def already_indexed?(session_id, file_mtime)
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "content",
        filter_by: "session_id:=#{session_id}",
        per_page: 1,
        include_fields: "file_mtime"
      )
      return false if result["found"] == 0

      existing_mtime = result.dig("hits", 0, "document", "file_mtime")
      existing_mtime == file_mtime
    rescue Typesense::Error::ObjectNotFound
      false
    end

    def delete_session(session_id)
      @client.collections[Config::COLLECTION_NAME].documents.delete(
        filter_by: "session_id:=#{session_id}"
      )
    rescue Typesense::Error::ObjectNotFound
      # Collection or documents don't exist yet
    end
  end
end
