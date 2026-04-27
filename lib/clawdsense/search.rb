# frozen_string_literal: true

module Clawdsense
  class Search
    def initialize
      @client = Config.client
    end

    def search(query, project: nil)
      params = {
        q: query,
        query_by: "content",
        per_page: 100,
        sort_by: "_text_match:desc,timestamp:desc",
        group_by: "session_id",
        group_limit: 3
      }

      params[:filter_by] = "cwd:/.*#{Regexp.escape(project)}.*/" if project

      result = @client.collections[Config::COLLECTION_NAME].documents.search(params)
      attach_neighbors!(result)
      result
    end

    def session_cwd(session_id)
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "content",
        filter_by: "session_id:=#{session_id}",
        per_page: 1,
        include_fields: "cwd"
      )

      return nil if result["found"] == 0

      result.dig("hits", 0, "document", "cwd")
    end

    private

    def attach_neighbors!(result)
      hits = all_hits(result)
      ids = hits.flat_map { |hit| [hit["document"]["prev_id"], hit["document"]["next_id"]] }.compact.uniq
      return if ids.empty?

      neighbors = fetch_by_id(ids)

      hits.each do |hit|
        doc = hit["document"]
        hit["prev"] = neighbors[doc["prev_id"]] if doc["prev_id"]
        hit["next"] = neighbors[doc["next_id"]] if doc["next_id"]
      end
    end

    def all_hits(result)
      (result["grouped_hits"] || []).flat_map { |group| group["hits"] }
    end

    def fetch_by_id(ids)
      ids.each_slice(50).flat_map { |batch| fetch_batch(batch) }
         .to_h { |doc| [doc["id"], doc] }
    end

    def fetch_batch(ids)
      result = @client.collections[Config::COLLECTION_NAME].documents.search(
        q: "*",
        query_by: "content",
        filter_by: "id:[#{ids.join(",")}]",
        per_page: ids.size,
        include_fields: "id,role,content,timestamp,prev_id"
      )
      (result["hits"] || []).map { |hit| hit["document"] }
    end
  end
end
