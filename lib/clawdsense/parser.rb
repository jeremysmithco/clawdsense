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

    attr_reader :records, :session_id, :project

    def initialize(file_path)
      @file_path = file_path
      @session_id = File.basename(file_path, ".jsonl")
      @project = File.basename(File.dirname(file_path))
      @records = File.readlines(file_path).filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def session_metadata
      @session_metadata ||= extract_session_metadata
    end

    def turns
      @turns ||= extract_turns
    end

    def turn_documents
      meta = session_metadata
      turns.each_with_index.map do |turn, i|
        turn_doc = {
          "id" => "#{session_id}_#{i}",
          "turn_number" => i,
          "timestamp" => to_epoch(turn[:timestamp]),
          "user_prompt" => turn[:user_prompt],
          "tools_used" => turn[:tools_used],
          "tool_count" => turn[:tools_used].size
        }

        turn_doc["assistant_text"] = turn[:assistant_text] if turn[:assistant_text] && !turn[:assistant_text].empty?
        turn_doc["thinking"] = turn[:thinking] if turn[:thinking] && !turn[:thinking].empty?
        turn_doc["duration_ms"] = turn[:duration_ms] if turn[:duration_ms]
        turn_doc["files_modified"] = turn[:files_modified] if turn[:files_modified]&.any?
        turn_doc["files_read"] = turn[:files_read] if turn[:files_read]&.any?
        turn_doc["bash_commands"] = turn[:bash_commands] if turn[:bash_commands]&.any?
        turn_doc["git_branch"] = turn[:git_branch] if turn[:git_branch]

        turn_doc.merge(meta)
      end
    end

    private

    def extract_session_metadata
      system_records = records.select { |r| r["type"] == "system" }
      assistant_records = records.select { |r| r["type"] == "assistant" }
      user_records = records.select { |r| r["type"] == "user" }
      summary_records = records.select { |r| r["type"] == "summary" }

      slug = system_records.filter_map { |r| r["slug"] }.first
      summary = summary_records.last&.dig("summary")
      cwd = (system_records + user_records).filter_map { |r| r["cwd"] }.first || ""
      model = assistant_records.filter_map { |r| r.dig("message", "model") }.first || "unknown"
      version = (system_records + user_records).filter_map { |r| r["version"] }.first || "unknown"

      {
        "session_id" => session_id,
        "project" => project,
        "cwd" => cwd,
        "model" => model,
        "claude_code_version" => version,
        "file_size_bytes" => File.size(@file_path)
      }.tap do |meta|
        meta["slug"] = slug if slug
        meta["summary"] = summary if summary
      end
    end

    def extract_turns
      human_prompts = extract_human_prompts
      return [] if human_prompts.empty?

      human_prompts.each_with_index.map do |prompt_record, i|
        next_prompt_time = human_prompts[i + 1]&.dig("timestamp")
        build_turn(prompt_record, next_prompt_time)
      end
    end

    def extract_human_prompts
      records.select { |r|
        next false unless r["type"] == "user"
        content = r.dig("message", "content")
        next false unless content.is_a?(String)
        next false if system_injected?(content)
        true
      }
    end

    def system_injected?(content)
      stripped = content.strip
      SYSTEM_INJECTED_PREFIXES.any? { |prefix| stripped.start_with?(prefix) }
    end

    def build_turn(prompt_record, next_prompt_time)
      prompt_uuid = prompt_record["uuid"]
      prompt_time = prompt_record["timestamp"]
      git_branch = prompt_record["gitBranch"]

      # Find assistant records for this turn
      # They either reference this prompt via parentUuid, or fall between this prompt and the next
      assistant_messages = records.select { |r|
        next false unless r["type"] == "assistant"
        if r["parentUuid"] == prompt_uuid
          true
        elsif prompt_time && r["timestamp"]
          after_prompt = r["timestamp"] >= prompt_time
          before_next = next_prompt_time.nil? || r["timestamp"] < next_prompt_time
          after_prompt && before_next
        else
          false
        end
      }

      # Merge streamed assistant messages — take the last (most complete) per message ID
      merged = merge_assistant_messages(assistant_messages)

      # Find matching turn_duration system record
      duration_record = records.find { |r|
        r["type"] == "system" &&
          r["subtype"] == "turn_duration" &&
          r["parentUuid"] == prompt_uuid
      }

      # Find file-history-snapshot records for this turn
      snapshot_files = extract_snapshot_files(prompt_uuid, prompt_time, next_prompt_time)

      {
        timestamp: prompt_time,
        user_prompt: prompt_record.dig("message", "content"),
        assistant_text: merged[:text],
        thinking: merged[:thinking],
        tools_used: merged[:tools].uniq,
        files_modified: (merged[:files_modified] + snapshot_files).uniq,
        files_read: merged[:files_read].uniq,
        bash_commands: merged[:bash_commands],
        duration_ms: duration_record&.dig("durationMs"),
        git_branch: git_branch
      }
    end

    def merge_assistant_messages(assistant_messages)
      # Group by message ID to handle streaming duplicates
      by_msg_id = assistant_messages.group_by { |r| r.dig("message", "id") || r["uuid"] }

      text_parts = []
      thinking_parts = []
      tools = []
      files_modified = []
      files_read = []
      bash_commands = []

      by_msg_id.each_value do |group|
        # Take the last record in each group (most complete due to streaming)
        record = group.max_by { |r| r["timestamp"] || "" }
        content_blocks = record.dig("message", "content") || []

        content_blocks.each do |block|
          case block["type"]
          when "text"
            text = block["text"]&.strip
            text_parts << text if text && !text.empty?
          when "thinking"
            thinking = block["thinking"]&.strip
            thinking_parts << thinking if thinking && !thinking.empty?
          when "tool_use"
            tool_name = block["name"]
            tools << tool_name if tool_name
            extract_file_refs(block, files_modified, files_read, bash_commands)
          end
        end
      end

      {
        text: text_parts.join("\n\n"),
        thinking: thinking_parts.join("\n\n"),
        tools: tools,
        files_modified: files_modified,
        files_read: files_read,
        bash_commands: bash_commands
      }
    end

    def extract_file_refs(tool_block, files_modified, files_read, bash_commands)
      name = tool_block["name"]
      input = tool_block["input"] || {}

      case name
      when "Edit", "Write", "NotebookEdit"
        path = input["file_path"] || input["notebook_path"]
        files_modified << path if path
      when "Read"
        path = input["file_path"]
        files_read << path if path
      when "Grep"
        path = input["path"]
        files_read << path if path
      when "Glob"
        path = input["path"]
        files_read << path if path
      when "Bash"
        cmd = input["command"]
        bash_commands << cmd if cmd
      end
    end

    def extract_snapshot_files(prompt_uuid, prompt_time, next_prompt_time)
      records.select { |r|
        next false unless r["type"] == "file-history-snapshot"
        ts = r.dig("snapshot", "timestamp") || r.dig("timestamp")
        next false unless ts
        after_prompt = prompt_time.nil? || ts >= prompt_time
        before_next = next_prompt_time.nil? || ts < next_prompt_time
        after_prompt && before_next
      }.flat_map { |r|
        backups = r.dig("snapshot", "trackedFileBackups") || {}
        backups.keys
      }
    end

    def to_epoch(timestamp)
      return 0 unless timestamp
      Time.parse(timestamp).to_i
    rescue ArgumentError
      0
    end
  end
end
