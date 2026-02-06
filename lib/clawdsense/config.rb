# frozen_string_literal: true

require "typesense"

module Clawdsense
  module Config
    COLLECTION_NAME = "clawdsense"

    COLLECTION_SCHEMA = {
      "name" => COLLECTION_NAME,
      "fields" => [
        {"name" => "session_id",          "type" => "string",   "facet" => true},
        {"name" => "project",             "type" => "string",   "facet" => true},
        {"name" => "slug",                "type" => "string",   "optional" => true},
        {"name" => "summary",             "type" => "string",   "optional" => true},
        {"name" => "cwd",                 "type" => "string"},
        {"name" => "model",               "type" => "string",   "facet" => true},
        {"name" => "claude_code_version", "type" => "string",   "facet" => true},
        {"name" => "git_branch",          "type" => "string",   "facet" => true, "optional" => true},
        {"name" => "file_size_bytes",     "type" => "int64"},

        {"name" => "turn_number",         "type" => "int32"},
        {"name" => "timestamp",           "type" => "int64"},
        {"name" => "duration_ms",         "type" => "int64",    "optional" => true},

        {"name" => "user_prompt",         "type" => "string"},
        {"name" => "assistant_text",      "type" => "string",   "optional" => true},
        {"name" => "thinking",            "type" => "string",   "optional" => true},

        {"name" => "tools_used",          "type" => "string[]", "facet" => true},
        {"name" => "tool_count",          "type" => "int32"},
        {"name" => "files_modified",      "type" => "string[]", "facet" => true, "optional" => true},
        {"name" => "files_read",          "type" => "string[]", "optional" => true},
        {"name" => "bash_commands",       "type" => "string[]", "optional" => true},

        {"name" => "embedding",           "type" => "float[]",
         "embed" => {
           "from" => ["user_prompt", "assistant_text"],
           "model_config" => {
             "model_name" => "ts/all-MiniLM-L12-v2"
           }
         }}
      ],
      "default_sorting_field" => "timestamp"
    }.freeze

    def self.client
      @client ||= Typesense::Client.new(
        nodes: [{host: "localhost", port: 8108, protocol: "http"}],
        api_key: api_key,
        connection_timeout_seconds: 10
      )
    end

    def self.api_key
      ENV.fetch("TYPESENSE_API_KEY", "xyz")
    end

    def self.ensure_collection!
      client.collections[COLLECTION_NAME].retrieve
    rescue Typesense::Error::ObjectNotFound
      begin
        client.collections.create(COLLECTION_SCHEMA)
      rescue Typesense::Error::ObjectAlreadyExists
        client.collections[COLLECTION_NAME].retrieve
      end
    end

    def self.projects_dir
      File.expand_path("~/.claude/projects")
    end
  end
end
