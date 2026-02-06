# frozen_string_literal: true

module Clawdsense
  class Indexer
    BATCH_SIZE = 40

    def initialize(project: nil, force: false)
      @project = project
      @force = force
      @client = Config.client
      @collection = Config.ensure_collection!
      @stats = {sessions: 0, turns: 0, skipped: 0, errors: 0}
    end

    def run
      files = session_files
      puts "Found #{files.size} session files"

      files.each do |file|
        index_file(file)
      end

      puts "\nDone. Indexed #{@stats[:sessions]} sessions (#{@stats[:turns]} turns), " \
           "skipped #{@stats[:skipped]}, errors #{@stats[:errors]}"
      @stats
    end

    private

    def session_files
      pattern = if @project
        File.join(Config.projects_dir, "*#{@project}*", "*.jsonl")
      else
        File.join(Config.projects_dir, "*", "*.jsonl")
      end
      Dir.glob(pattern).sort
    end

    def index_file(file)
      session_id = File.basename(file, ".jsonl")
      file_size = File.size(file)

      unless @force
        if already_indexed?(session_id, file_size)
          @stats[:skipped] += 1
          return
        end
      end

      parser = Parser.new(file)
      docs = parser.turn_documents

      if docs.empty?
        @stats[:skipped] += 1
        return
      end

      # Delete existing turns for this session before re-importing
      delete_session(session_id)

      # Import in batches
      docs.each_slice(BATCH_SIZE) do |batch|
        results = @client.collections[Config::COLLECTION_NAME].documents.import(batch, action: :upsert)
        errors = results.select { |r| r["success"] == false }
        if errors.any?
          $stderr.puts "  Errors in #{session_id}: #{errors.first(3).map { |e| e["error"] }.join(", ")}"
          @stats[:errors] += errors.size
        end
      end

      @stats[:sessions] += 1
      @stats[:turns] += docs.size
      project = parser.project
      slug = parser.session_metadata["slug"]
      label = slug ? "#{slug} (#{session_id[0..7]})" : session_id[0..7]
      puts "  #{project} / #{label} — #{docs.size} turns"
    rescue => e
      $stderr.puts "  Error processing #{file}: #{e.message}"
      @stats[:errors] += 1
    end

    def already_indexed?(session_id, file_size)
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "user_prompt",
        filter_by: "session_id:=#{session_id}",
        per_page: 1,
        include_fields: "file_size_bytes"
      )
      return false if result["found"] == 0

      existing_size = result.dig("hits", 0, "document", "file_size_bytes")
      existing_size == file_size
    rescue Typesense::Error::ObjectNotFound
      false
    end

    def delete_session(session_id)
      @client.collections[Config::COLLECTION_NAME].documents.delete(
        filter_by: "session_id:=#{session_id}"
      )
    rescue Typesense::Error::ObjectNotFound
      # Collection or documents don't exist yet, that's fine
    end
  end
end
