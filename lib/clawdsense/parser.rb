# frozen_string_literal: true

require "json"
require "time"

module Clawdsense
  class Parser
    SYSTEM_INJECTED_PREFIXES = [
      "<local-command-caveat>",
      "<command-name>",
      "<local-command-stdout>",
      "<command-message>",
      "<system-reminder>"
    ].freeze

    attr_reader :session_id

    def initialize(file_path)
      @file_path = file_path
      @session_id = File.basename(file_path, ".jsonl")
      @file_mtime = File.mtime(file_path).to_i
    end

    def documents
      entries = []

      File.foreach(@file_path) do |line|
        record = JSON.parse(line)
        doc = parse_record(record)
        entries << doc if doc
      rescue JSON::ParserError
        next
      end

      entries.each_with_index do |doc, i|
        doc["prev_id"] = entries[i - 1]["id"] if i > 0
        doc["next_id"] = entries[i + 1]["id"] if i < entries.size - 1
      end

      entries
    end

    private

    def parse_record(record)
      case record["type"]
      when "user"
        parse_user(record)
      when "assistant"
        parse_assistant(record)
      end
    end

    def parse_user(record)
      return nil if record["isMeta"]

      content = record.dig("message", "content")
      return nil unless content.is_a?(String)
      return nil if system_injected?(content)

      build_document(record, role: "user", content: content)
    end

    def parse_assistant(record)
      blocks = record.dig("message", "content")
      return nil unless blocks.is_a?(Array)

      text_block = blocks.first
      return nil unless text_block&.dig("type") == "text"

      content = text_block["text"]&.strip
      return nil if content.nil? || content.empty?

      build_document(record, role: "assistant", content: content)
    end

    def build_document(record, role:, content:)
      {
        "id" => record["uuid"],
        "session_id" => @session_id,
        "role" => role,
        "content" => content,
        "timestamp" => to_epoch(record["timestamp"]),
        "cwd" => record["cwd"] || "",
        "file_mtime" => @file_mtime
      }
    end

    def system_injected?(content)
      stripped = content.strip
      SYSTEM_INJECTED_PREFIXES.any? { |prefix| stripped.start_with?(prefix) }
    end

    def to_epoch(timestamp)
      return 0 unless timestamp
      Time.parse(timestamp).to_i
    rescue ArgumentError
      0
    end
  end
end
