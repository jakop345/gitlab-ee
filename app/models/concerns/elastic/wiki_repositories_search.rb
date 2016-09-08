module Elastic
  module WikiRepositoriesSearch
    extend ActiveSupport::Concern

    included do
      include Elasticsearch::Git::Repository

      index_name [Rails.application.class.parent_name.downcase, Rails.env].join('-')
    end

    module ClassMethods
      def self.repositories_count
        Project.with_wiki_enabled.count
      end

      def self.import
        Project.with_wiki_enabled.find_each do |project|
          unless project.wiki.empty?
            project.wiki.index_blobs
          end
        end
      end
    end

    def repository_id
      "wiki_#{project.id}"
    end

    def client_for_indexing
      self.__elasticsearch__.client
    end
  end
end
