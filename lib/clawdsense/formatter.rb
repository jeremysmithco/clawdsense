# frozen_string_literal: true

require "time"

module Clawdsense
  class Formatter
    BOLD = "\e[1m"
    DIM = "\e[2m"
    CYAN = "\e[36m"
    GREEN = "\e[32m"
    YELLOW = "\e[33m"
    RESET = "\e[0m"

    def format_search_results(results)
      grouped = results["grouped_hits"]
      if grouped
        format_grouped_results(grouped, results["found"])
      else
        format_flat_results(results["hits"], results["found"])
      end
    end

    def format_session_list(results)
      grouped = results["grouped_hits"] || []
      return "No sessions found.\n" if grouped.empty?

      lines = []
      grouped.each do |group|
        doc = group["hits"].first&.dig("document")
        next unless doc
        lines << format_session_summary(doc)
      end
      lines.join("\n")
    end

    def format_session_detail(results)
      hits = results["hits"] || []
      return "No turns found for this session.\n" if hits.empty?

      first = hits.first["document"]
      lines = [session_header(first), ""]

      hits.each do |hit|
        doc = hit["document"]
        lines << format_turn_detail(doc)
      end
      lines.join("\n")
    end

    def format_stats(collection_info)
      lines = [
        "#{BOLD}Clawdsense Stats#{RESET}",
        "",
        "  Documents:  #{collection_info["num_documents"]}",
        "  Fields:     #{collection_info["fields"]&.size}",
        "  Collection: #{collection_info["name"]}",
        ""
      ]
      lines.join("\n")
    end

    private

    def format_grouped_results(grouped, total_found)
      return "No results found.\n" if grouped.empty?

      session_count = grouped.size
      turn_count = grouped.sum { |g| g["hits"].size }

      lines = ["", " #{BOLD}#{session_count} sessions, #{turn_count} turns matched#{RESET} (#{total_found} total)", ""]

      grouped.each do |group|
        hits = group["hits"]
        first_doc = hits.first["document"]
        lines << session_header(first_doc)
        lines << ""

        hits.each do |hit|
          doc = hit["document"]
          lines << format_turn_hit(hit)
        end
        lines << ""
      end
      lines.join("\n")
    end

    def format_flat_results(hits, total_found)
      return "No results found.\n" if hits.nil? || hits.empty?

      lines = ["", " #{BOLD}#{hits.size} turns matched#{RESET} (#{total_found} total)", ""]

      hits.each do |hit|
        lines << format_turn_hit(hit)
      end
      lines.join("\n")
    end

    def session_header(doc)
      slug = doc["slug"]
      sid = doc["session_id"]
      summary = doc["summary"]
      date = format_time(doc["timestamp"])
      branch = doc["git_branch"]
      model = doc["model"]

      header = "#{CYAN}--- #{slug || sid[0..7]}#{RESET} #{DIM}#{sid}#{RESET}"
      header += "\n #{summary}" if summary
      header += "\n #{DIM}#{date}#{RESET}"
      parts = []
      parts << "branch: #{branch}" if branch
      parts << "model: #{model}" if model
      header += "  #{DIM}#{parts.join("  ")}#{RESET}" if parts.any?
      header
    end

    def format_turn_hit(hit)
      doc = hit["document"]
      turn_num = doc["turn_number"]
      prompt = truncate(doc["user_prompt"], 120)
      tools = doc["tools_used"] || []
      files = doc["files_modified"] || []

      line = " #{YELLOW}Turn #{turn_num}:#{RESET} \"#{prompt}\""

      # Show highlight snippet when match is in assistant_text (not visible in prompt)
      snippet = assistant_highlight(hit)
      line += "\n   #{DIM}=> ...#{render_highlight(snippet)}...#{RESET}" if snippet

      details = []
      details << "Tools: #{tools.join(", ")}" if tools.any?
      details << "Files: #{files.map { |f| File.basename(f) }.uniq.join(", ")}" if files.any?
      line += "\n   #{DIM}-> #{details.join("  ")}#{RESET}" if details.any?
      line
    end

    def format_turn_detail(doc)
      turn_num = doc["turn_number"]
      prompt = doc["user_prompt"]
      assistant = doc["assistant_text"]
      tools = doc["tools_used"] || []
      duration = doc["duration_ms"]

      lines = []
      lines << "#{YELLOW}--- Turn #{turn_num} ---#{RESET}"
      lines << "#{BOLD}User:#{RESET} #{prompt}"

      if assistant && !assistant.empty?
        lines << "#{BOLD}Assistant:#{RESET} #{truncate(assistant, 500)}"
      end

      meta = []
      meta << "tools: #{tools.join(", ")}" if tools.any?
      meta << "duration: #{(duration / 1000.0).round(1)}s" if duration
      lines << "#{DIM}#{meta.join("  ")}#{RESET}" if meta.any?
      lines << ""
      lines.join("\n")
    end

    def format_session_summary(doc)
      slug = doc["slug"]
      summary = doc["summary"]
      project = doc["project"]
      date = format_time(doc["timestamp"])
      sid = doc["session_id"]

      line = "  #{CYAN}#{slug || sid[0..7]}#{RESET} #{DIM}#{sid}#{RESET}"
      line += "\n    #{summary}" if summary
      line += "\n    #{DIM}#{project}  #{date}#{RESET}"
      line
    end

    def assistant_highlight(hit)
      highlights = hit["highlights"] || []
      match = highlights.find { |h| h["field"] == "assistant_text" }
      return nil unless match

      snippet = match["snippet"]
      return nil unless snippet && !snippet.empty?

      truncate(snippet, 150)
    end

    # Convert <mark>...</mark> to bold terminal highlighting
    def render_highlight(text)
      return "" unless text
      text.gsub("<mark>", "\e[1;33m").gsub("</mark>", "\e[0;2m")
    end

    def format_time(epoch)
      return "unknown" unless epoch.is_a?(Integer) && epoch > 0
      Time.at(epoch).strftime("%Y-%m-%d %H:%M")
    end

    def truncate(str, max)
      return "" unless str
      str.length > max ? "#{str[0..max]}..." : str
    end
  end
end
