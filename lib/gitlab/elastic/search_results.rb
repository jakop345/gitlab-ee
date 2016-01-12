module Gitlab
  module Elastic
    class SearchResults
      attr_reader :query

      # Limit search results by passed project ids
      # It allows us to search only for projects user has access to
      attr_reader :limit_project_ids

      def initialize(limit_project_ids, query)
        @limit_project_ids = limit_project_ids || Project.all
        @query = Shellwords.shellescape(query) if query.present?
      end

      def objects(scope, page = nil)
        case scope
        when 'projects'
          projects
        when 'issues'
          issues
        when 'merge_requests'
          merge_requests
        when 'milestones'
          milestones
        else
          Kaminari.paginate_array([])
        end
      end

      def total_count
        @total_count ||= projects_count + issues_count + merge_requests_count# + milestones_count
      end

      def projects_count
        @projects_count ||= projects.total_count
      end

      def issues_count
        @issues_count ||= issues.total_count
      end

      def merge_requests_count
        @merge_requests_count ||= merge_requests.total_count
      end

      # def milestones_count
      #   @milestones_count ||= milestones.total_count
      # end

      def empty?
        total_count.zero?
      end

      private

      def projects
        opt = {
          pids: projects_ids,
          fields: %w(name^10 path^9 description^5
             name_with_namespace^2 path_with_namespace),
          highlight: true
        }

        @projects = Project.elastic_search(query, options: opt)
      end

      def issues
        opt = {
          projects_ids: projects_ids
        }

        if query =~ /#(\d+)\z/
          issues = Issue.where(project_id: limit_project_ids).where(iid: $1)
        else
          issues = Issue.elastic_search(query, options: opt)
        end
      end

      # def milestones
      #   opt = {
      #     projects_ids: projects_ids
      #   }

      #   milestones = Milestone.elastic_search(query, options: opt)
      # end

      def merge_requests
        opt = {
          projects_ids: projects_ids,
          highlight: true
        }

        if query =~ /[#!](\d+)\z/
          merge_requests = MergeRequest.in_projects(limit_project_ids).where(iid: $1)
        else
          merge_requests = MergeRequest.elastic_search(query, options: opt)
        end
      end

      def default_scope
        'projects'
      end

      def per_page
        20
      end
    end
  end
end
