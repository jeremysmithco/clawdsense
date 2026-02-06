# frozen_string_literal: true

module Clawdsense
  class Search
    def initialize
      @client = Config.client
    end

    # Hybrid keyword + semantic search (default)
    def hybrid(query, **opts)
      search(query, mode: :hybrid, **opts)
    end

    # Keyword-only search
    def keyword(query, **opts)
      search(query, mode: :keyword, **opts)
    end

    # Semantic-only search
    def semantic(query, **opts)
      search(query, mode: :semantic, **opts)
    end

    # Show all turns for a session (supports prefix matching)
    def session_turns(session_id)
      full_id = resolve_session_id(session_id)
      unless full_id
        return {"hits" => [], "found" => 0, "error" => "No session found matching '#{session_id}'"}
      end

      @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "user_prompt",
        filter_by: "session_id:=#{full_id}",
        sort_by: "turn_number:asc",
        per_page: 250,
        exclude_fields: "embedding"
      )
    end

    # Resolve a short prefix to a full session ID
    def resolve_session_id(prefix)
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "user_prompt",
        filter_by: "session_id:=#{prefix}",
        per_page: 1,
        include_fields: "session_id"
      )
      return prefix if result["found"] > 0

      # Try prefix match by faceting
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "user_prompt",
        facet_by: "session_id",
        max_facet_values: 250,
        per_page: 0
      )
      facets = result.dig("facet_counts", 0, "counts") || []
      matches = facets.select { |f| f["value"].start_with?(prefix) }

      case matches.size
      when 1 then matches.first["value"]
      when 0 then nil
      else
        $stderr.puts "Ambiguous prefix '#{prefix}', matches #{matches.size} sessions:"
        matches.first(5).each { |m| $stderr.puts "  #{m["value"]}" }
        nil
      end
    end

    # List recent sessions (grouped)
    def list_sessions(project: nil, per_page: 20)
      params = {
        q: "*",
        query_by: "user_prompt",
        group_by: "session_id",
        group_limit: 1,
        sort_by: "timestamp:desc",
        per_page: per_page,
        exclude_fields: "embedding,thinking"
      }
      params[:filter_by] = "project:=#{project}" if project
      @client.collections[Config::COLLECTION_NAME].documents.search(params)
    end

    # Collection stats
    def stats
      @client.collections[Config::COLLECTION_NAME].retrieve
    end

    private

    def search(query, mode:, project: nil, branch: nil, file: nil, session_id: nil, group_by_session: true, per_page: 10)
      params = {per_page: per_page, exclude_fields: "embedding,thinking"}

      case mode
      when :hybrid
        params[:q] = query
        params[:query_by] = "user_prompt,assistant_text,embedding"
        params[:vector_query] = "embedding:([], k:20, alpha:0.3)"
      when :keyword
        params[:q] = query
        params[:query_by] = "user_prompt,assistant_text"
      when :semantic
        params[:q] = query
        params[:query_by] = "embedding"
        params[:vector_query] = "embedding:([], k:20, distance_threshold:0.5)"
      end

      # Filters
      filters = []
      filters << "project:=#{project}" if project
      filters << "git_branch:=#{branch}" if branch
      filters << "files_modified:=#{file}" if file
      filters << "session_id:=#{session_id}" if session_id
      params[:filter_by] = filters.join(" && ") if filters.any?

      # Grouping
      if group_by_session && !session_id
        params[:group_by] = "session_id"
        params[:group_limit] = 3
      end

      params[:sort_by] = "timestamp:desc" unless mode == :semantic

      @client.collections[Config::COLLECTION_NAME].documents.search(params)
    end
  end
end
