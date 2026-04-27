# frozen_string_literal: true

require "typesense"

module Clawdsense
  module Config
    COLLECTION_NAME = "clawdsense"

    COLLECTION_SCHEMA = {
      "name" => COLLECTION_NAME,
      "token_separators" => ["_", "-", ".", "/", ":"],
      "fields" => [
        {"name" => "session_id",          "type" => "string",   "facet" => true},
        {"name" => "role",                "type" => "string"},
        {"name" => "content",             "type" => "string"},
        {"name" => "timestamp",           "type" => "int64"},

        {"name" => "cwd",                 "type" => "string"},

        {"name" => "prev_id",             "type" => "string",   "optional" => true},
        {"name" => "next_id",             "type" => "string",   "optional" => true},

        {"name" => "file_mtime",          "type" => "int64"}
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
