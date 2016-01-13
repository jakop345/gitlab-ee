module SnippetsSearch
  extend ActiveSupport::Concern

  included do
    include ApplicationSearch

    mappings do
      indexes :id,          type: :integer, index: :not_analyzed

      indexes :title,       type: :string, index_options: 'offsets', search_analyzer: :search_analyzer, analyzer: :my_analyzer
      indexes :file_name,   type: :string, index_options: 'offsets', search_analyzer: :search_analyzer, analyzer: :my_analyzer
      indexes :content,     type: :string, index_options: 'offsets', search_analyzer: :search_analyzer, analyzer: :my_analyzer
      indexes :created_at,  type: :date
      indexes :updated_at,  type: :date
      indexes :state,       type: :string

      indexes :project_id,  type: :integer, index: :not_analyzed
      indexes :author_id,   type: :integer, index: :not_analyzed

      indexes :project,     type: :nested
      indexes :author,      type: :nested

      indexes :title_sort, type: :string, index: :not_analyzed
      indexes :updated_at_sort, type: :date,   index: :not_analyzed
      indexes :created_at_sort, type: :string, index: :not_analyzed
    end

    def as_indexed_json(options = {})
      as_json(
        include: {
          project:  { only: :id },
          author:   { only: :id }
        }
      ).merge({
        title_sort: title.downcase,
        updated_at_sort: updated_at,
        created_at_sort: created_at
      })
    end

    def self.elastic_search(query, options: {})
      if options[:in].blank?
        options[:in] = %w(title file_name)
      else
        options[:in].push(%w(title file_name) - options[:in])
      end

      query_hash = {
        query: {
          filtered: {
            query: {
              multi_match: {
                fields: options[:in],
                query: "#{query}",
                operator: :and
              }
            },
          },
        }
      }

      if query.blank?
        query_hash[:query][:filtered][:query] = { match_all: {}}
        query_hash[:track_scores] = true
      end

      if options[:ids]
        query_hash[:query][:filtered][:filter] ||= { and: [] }
        query_hash[:query][:filtered][:filter][:and] << {
          terms: {
            id: [options[:ids]].flatten
          }
        }
      end

      if options[:highlight]
        query_hash[:highlight] = { fields: options[:in].inject({}) { |a, o| a[o.to_sym] = {} } }
      end

      self.__elasticsearch__.search(query_hash)
    end

    def self.elastic_search_code(query, options: {})
      query_hash = {
        query: {
          filtered: {
            query: {match: {content: query}},
          },
        }
      }

      if options[:ids]
        query_hash[:query][:filtered][:filter] ||= { and: [] }
        query_hash[:query][:filtered][:filter][:and] << {
          terms: {
            id: [options[:ids]].flatten
          }
        }
      end

      if options[:highlight]
        query_hash[:highlight] = { fields: options[:in].inject({}) { |a, o| a[o.to_sym] = {} } }
      end

      self.__elasticsearch__.search(query_hash)
    end
  end
end
