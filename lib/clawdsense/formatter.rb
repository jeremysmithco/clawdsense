# frozen_string_literal: true

require "time"
require "io/console"

module Clawdsense
  class Formatter
    BOLD = "\e[1m"
    DIM = "\e[2m"
    YELLOW = "\e[33m"
    CYAN = "\e[36m"
    RESET = "\e[0m"

    MAX_CONTENT_LENGTH = 240

    def initialize
      @width = (IO.console&.winsize&.[](1) || 80).clamp(40, 90)
    end

    def format_search_results(results)
      groups = results["grouped_hits"] || []
      return "No results found.\n" if groups.empty?

      found = results["found"]
      session_count = groups.size
      lines = ["#{BOLD}#{session_count} sessions#{RESET} (#{found} matching entries)"]

      groups.each_with_index do |group, i|
        lines << format_group(group, i)
      end

      lines.join("\n\n")
    end

    private

    def format_group(group, index)
      hits = group["hits"]
      matches = group["found"] || hits.size
      lines = [session_header(hits.first["document"], index, matches)]

      chronological_entries(hits).each do |entry|
        lines << format_entry(entry[:doc], highlight: !entry[:hit].nil?, hit: entry[:hit])
      end

      lines.join("\n\n")
    end

    def chronological_entries(hits)
      by_id = {}
      hits.each do |hit|
        doc = hit["document"]
        by_id[hit["prev"]["id"]] ||= {doc: hit["prev"], hit: nil} if hit["prev"]
        by_id[doc["id"]] = {doc: doc, hit: hit}
        by_id[hit["next"]["id"]] ||= {doc: hit["next"], hit: nil} if hit["next"]
      end
      by_id.values.sort_by { |e| e[:doc]["timestamp"] || 0 }
    end

    def session_header(doc, index, matches)
      sid = doc["session_id"]
      cwd = doc["cwd"]
      timestamp = doc["timestamp"]
      relative = relative_time(timestamp)
      absolute = format_time(timestamp)

      lines = [separator]
      lines << "#{CYAN}#{BOLD}#{index+1}. #{sid}#{RESET}"
      lines << "#{CYAN}#{DIM}#{cwd}#{RESET}"
      lines << "#{BOLD}#{relative}#{RESET}  #{DIM}#{absolute}#{RESET}  #{YELLOW}#{matches} #{matches == 1 ? "match" : "matches"}#{RESET}"
      lines << separator
      lines.join("\n")
    end

    def separator
      "#{DIM}#{"─" * @width}#{RESET}"
    end

    def format_entry(entry, highlight: false, hit: nil)
      role = entry["role"]
      content = (entry["content"] || "").strip
      prefix = (role == "user") ? "❯" : "⏺"

      if highlight && hit
        snippet = highlighted_snippet(hit, content)
      else
        snippet = truncate(content, MAX_CONTENT_LENGTH)
      end

      snippet = word_wrap(snippet, @width - 2)
      snippet = render_marks(snippet) if highlight

      formatted_lines = snippet.lines.map.with_index do |line, i|
        pad = (i == 0) ? "#{prefix} " : "  "
        body = "#{pad}#{line.chomp}"
        highlight ? body : "#{DIM}#{body}#{RESET}"
      end

      formatted_lines.join("\n")
    end

    def highlighted_snippet(hit, content)
      highlights = hit["highlights"] || []
      match = highlights.find { |h| h["field"] == "content" }
      snippet = match&.dig("snippet")
      return truncate(content, MAX_CONTENT_LENGTH) unless snippet

      plain = snippet.gsub("<mark>", "").gsub("</mark>", "")
      prefix = content.start_with?(plain) ? "" : "..."
      suffix = content.end_with?(plain) ? "" : "..."
      "#{prefix}#{snippet}#{suffix}"
    end

    def render_marks(text)
      in_mark = false
      text.split("\n").map do |line|
        line = "<mark>" + line if in_mark
        opens = line.scan("<mark>").size
        closes = line.scan("</mark>").size

        if opens > closes
          line += "</mark>"
          in_mark = true
        else
          in_mark = false
        end

        line.gsub("<mark>", YELLOW).gsub("</mark>", RESET)
      end.join("\n")
    end

    def relative_time(epoch)
      return "unknown" unless epoch.is_a?(Integer) && epoch > 0

      seconds = Time.now.to_i - epoch
      return "just now" if seconds < 60

      minutes = seconds / 60
      return "#{minutes}m ago" if minutes < 60

      hours = minutes / 60
      return "#{hours}h ago" if hours < 24

      days = hours / 24
      return "#{days}d ago" if days < 30

      months = days / 30
      return "#{months}mo ago" if months < 12

      years = days / 365
      "#{years}y ago"
    end

    def format_time(epoch)
      return "" unless epoch.is_a?(Integer) && epoch > 0
      Time.at(epoch).strftime("%Y-%m-%d %H:%M")
    end

    def truncate(str, max)
      return "" unless str
      str.length > max ? "#{str[0, max]}..." : str
    end

    def word_wrap(text, width)
      text.split("\n").flat_map { |line| wrap_line(line, width) }.join("\n")
    end

    def wrap_line(line, width)
      return [line] if line.length <= width

      result = []
      current = ""
      line.split(/(\s+)/).each do |part|
        if (current + part).length > width && !current.empty?
          result << current.rstrip
          current = part.lstrip
        else
          current += part
        end
      end
      result << current.rstrip unless current.empty?
      result
    end
  end
end
