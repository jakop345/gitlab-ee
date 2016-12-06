module API
  class API < Grape::API
    include APIGuard
    version 'v3', using: :path

    before { allow_access_with_scope :api }

    rescue_from Gitlab::Access::AccessDeniedError do
      rack_response({ 'message' => '403 Forbidden' }.to_json, 403)
    end

    rescue_from ActiveRecord::RecordNotFound do
      rack_response({ 'message' => '404 Not found' }.to_json, 404)
    end

    # Retain 405 error rather than a 500 error for Grape 0.15.0+.
    # See: https://github.com/ruby-grape/grape/commit/252bfd27c320466ec3c0751812cf44245e97e5de
    rescue_from Grape::Exceptions::Base do |e|
      error! e.message, e.status, e.headers
    end

    rescue_from :all do |exception|
      handle_api_exception(exception)
    end

    format :json
    content_type :txt, "text/plain"

    # Ensure the namespace is right, otherwise we might load Grape::API::Helpers
    helpers ::SentryHelper
    helpers ::API::Helpers

    # Keep in alphabetical order
    mount ::API::AccessRequests
    mount ::API::AwardEmoji
    mount ::API::Boards
    mount ::API::Branches
    mount ::API::BroadcastMessages
    mount ::API::Builds
    mount ::API::Commits
    mount ::API::CommitStatuses
    mount ::API::DeployKeys
    mount ::API::Deployments
    mount ::API::Environments
    mount ::API::Files
    mount ::API::Groups
    mount ::API::Geo
    mount ::API::Internal
    mount ::API::Issues
    mount ::API::Keys
    mount ::API::Labels
    mount ::API::Ldap
    mount ::API::LdapGroupLinks
    mount ::API::License
    mount ::API::Lint
    mount ::API::Members
    mount ::API::MergeRequestDiffs
    mount ::API::MergeRequests
    mount ::API::Milestones
    mount ::API::Namespaces
    mount ::API::Notes
    mount ::API::NotificationSettings
    mount ::API::Pipelines
    mount ::API::ProjectGitHook # TODO: Should be removed after 8.11 is released
    mount ::API::ProjectHooks
    mount ::API::ProjectPushRule
    mount ::API::Projects
    mount ::API::ProjectSnippets
    mount ::API::Repositories
    mount ::API::Runners
    mount ::API::Services
    mount ::API::Session
    mount ::API::Settings
    mount ::API::SidekiqMetrics
    mount ::API::Subscriptions
    mount ::API::SystemHooks
    mount ::API::Tags
    mount ::API::Templates
    mount ::API::Todos
    mount ::API::Triggers
    mount ::API::Users
    mount ::API::Variables
    mount ::API::Version

    route :any, '*path' do
      error!('404 Not Found', 404)
    end
  end
end
