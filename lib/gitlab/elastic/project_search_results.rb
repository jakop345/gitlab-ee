module Gitlab
  module Elastic
    class ProjectSearchResults < SearchResults
      attr_reader :project, :repository_ref

      def initialize(project_id, query, repository_ref = nil)
        @project = Project.find(project_id)

        @repository_ref = if repository_ref.present?
                            repository_ref
                          else
                            nil
                          end
        @query = query
      end

      def objects(scope, page = nil)
        case scope
        when 'notes'
          notes.records.page(page).per(per_page)
        when 'blobs'
          Kaminari.paginate_array(blobs).page(page).per(per_page)
        when 'wiki_blobs'
          Kaminari.paginate_array(wiki_blobs).page(page).per(per_page)
        when 'commits'
          Kaminari.paginate_array(commits).page(page).per(per_page)
        else
          super
        end
      end

      def total_count
        @total_count ||= issues_count + merge_requests_count + blobs_count +
                         notes_count + wiki_blobs_count + commits_count
      end

      def blobs_count
        @blobs_count ||= blobs.total_count
      end

      def notes_count
        @notes_count ||= notes.total_count
      end

      def wiki_blobs_count
        @wiki_blobs_count ||= wiki_blobs.total_count
      end

      def commits_count
        @commits_count ||= commits.count
      end

      private

      def blobs
        Kaminari.paginate_array([])
        # if project.empty_repo? || query.blank?
        #   []
        # else
        #   project.repository.search_files(query, repository_ref)
        # end
      end

      def wiki_blobs
        Kaminari.paginate_array([])
        # if project.wiki_enabled? && query.present?
        #   project_wiki = ProjectWiki.new(project)

        #   unless project_wiki.empty?
        #     project_wiki.search_files(query)
        #   else
        #     []
        #   end
        # else
        #   []
        # end
      end

      def notes
        opt = {
          project_ids: limit_project_ids
        }

        Note.elastic_search(query, options: opt)
      end

      def commits
        if project.empty_repo? || query.blank?
          []
        else
          project.repository.find_commits_by_message_with_elastic(query)
        end
      end

      def limit_project_ids
        [project.id]
      end
    end
  end
end
