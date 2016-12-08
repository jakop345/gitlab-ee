module API
  module Entities
    class UserSafe < Grape::Entity
      expose :name, :username
    end

    class UserBasic < UserSafe
      expose :id, :state, :avatar_url

      expose :web_url do |user, options|
        Gitlab::Routing.url_helpers.user_url(user)
      end
    end

    class User < UserBasic
      expose :created_at
      expose :is_admin?, as: :is_admin
      expose :bio, :location, :skype, :linkedin, :twitter, :website_url, :organization
    end

    class Identity < Grape::Entity
      expose :provider, :extern_uid
    end

    class UserFull < User
      expose :last_sign_in_at
      expose :confirmed_at
      expose :email
      expose :theme_id, :color_scheme_id, :projects_limit, :current_sign_in_at
      expose :identities, using: Entities::Identity
      expose :can_create_group?, as: :can_create_group
      expose :can_create_project?, as: :can_create_project
      expose :two_factor_enabled?, as: :two_factor_enabled
      expose :external
    end

    class UserLogin < UserFull
      expose :private_token
    end

    class Email < Grape::Entity
      expose :id, :email
    end

    class Hook < Grape::Entity
      expose :id, :url, :created_at, :push_events, :tag_push_events
      expose :enable_ssl_verification
    end

    class ProjectHook < Hook
      expose :project_id, :issues_events, :merge_requests_events
      expose :note_events, :build_events, :pipeline_events, :wiki_page_events
    end

    class ProjectPushRule < Grape::Entity
      expose :id, :project_id, :created_at
      expose :commit_message_regex, :deny_delete_tag
    end

    class BasicProjectDetails < Grape::Entity
      expose :id
      expose :http_url_to_repo, :web_url
      expose :name, :name_with_namespace
      expose :path, :path_with_namespace
    end

    class SharedGroup < Grape::Entity
      expose :group_id
      expose :group_name do |group_link, options|
        group_link.group.name
      end
      expose :group_access, as: :group_access_level
    end

    class Project < Grape::Entity
      expose :id, :description, :default_branch, :tag_list
      expose :public?, as: :public
      expose :archived?, as: :archived
      expose :visibility_level, :ssh_url_to_repo, :http_url_to_repo, :web_url
      expose :owner, using: Entities::UserBasic, unless: ->(project, options) { project.group }
      expose :name, :name_with_namespace
      expose :path, :path_with_namespace
      expose :container_registry_enabled

      # Expose old field names with the new permissions methods to keep API compatible
      expose(:issues_enabled) { |project, options| project.feature_available?(:issues, options[:user]) }
      expose(:merge_requests_enabled) { |project, options| project.feature_available?(:merge_requests, options[:user]) }
      expose(:wiki_enabled) { |project, options| project.feature_available?(:wiki, options[:user]) }
      expose(:builds_enabled) { |project, options| project.feature_available?(:builds, options[:user]) }
      expose(:snippets_enabled) { |project, options| project.feature_available?(:snippets, options[:user]) }

      expose :created_at, :last_activity_at
      expose :shared_runners_enabled
      expose :lfs_enabled?, as: :lfs_enabled
      expose :creator_id
      expose :namespace
      expose :forked_from_project, using: Entities::BasicProjectDetails, if: lambda{ |project, options| project.forked? }
      expose :avatar_url
      expose :star_count, :forks_count
      expose :open_issues_count, if: lambda { |project, options| project.feature_available?(:issues, options[:user]) && project.default_issues_tracker? }
      expose :runners_token, if: lambda { |_project, options| options[:user_can_admin_project] }
      expose :public_builds
      expose :shared_with_groups do |project, options|
        SharedGroup.represent(project.project_group_links.all, options)
      end
      expose :repository_storage, if: lambda { |_project, options| options[:user].try(:admin?) }
      expose :only_allow_merge_if_build_succeeds
      expose :request_access_enabled
      expose :only_allow_merge_if_all_discussions_are_resolved
      expose :approvals_before_merge
    end

    class Member < UserBasic
      expose :access_level do |user, options|
        member = options[:member] || options[:source].members.find_by(user_id: user.id)
        member.access_level
      end
      expose :expires_at do |user, options|
        member = options[:member] || options[:source].members.find_by(user_id: user.id)
        member.expires_at
      end
    end

    class AccessRequester < UserBasic
      expose :requested_at do |user, options|
        access_requester = options[:access_requester] || options[:source].requesters.find_by(user_id: user.id)
        access_requester.requested_at
      end
    end

    class LdapGroupLink < Grape::Entity
      expose :cn, :group_access, :provider
    end

    class Group < Grape::Entity
      expose :id, :name, :path, :description, :visibility_level

      expose :ldap_cn, :ldap_access
      expose :ldap_group_links,
        using: Entities::LdapGroupLink,
        if: lambda { |group, options| group.ldap_group_links.any? }

      expose :lfs_enabled?, as: :lfs_enabled
      expose :avatar_url
      expose :web_url
      expose :request_access_enabled
    end

    class GroupDetail < Group
      expose :projects, using: Entities::Project
      expose :shared_projects, using: Entities::Project
    end

    class RepoBranch < Grape::Entity
      expose :name

      expose :commit do |repo_branch, options|
        options[:project].repository.commit(repo_branch.dereferenced_target)
      end

      expose :merged do |repo_branch, options|
        options[:project].repository.merged_to_root_ref?(repo_branch.name)
      end

      expose :protected do |repo_branch, options|
        options[:project].protected_branch?(repo_branch.name)
      end

      expose :developers_can_push do |repo_branch, options|
        project = options[:project]
        access_levels = project.protected_branches.matching(repo_branch.name).map(&:push_access_levels).flatten
        access_levels.any? { |access_level| access_level.access_level == Gitlab::Access::DEVELOPER }
      end

      expose :developers_can_merge do |repo_branch, options|
        project = options[:project]
        access_levels = project.protected_branches.matching(repo_branch.name).map(&:merge_access_levels).flatten
        access_levels.any? { |access_level| access_level.access_level == Gitlab::Access::DEVELOPER }
      end
    end

    class RepoTreeObject < Grape::Entity
      expose :id, :name, :type, :path

      expose :mode do |obj, options|
        filemode = obj.mode.to_s(8)
        filemode = "0" + filemode if filemode.length < 6
        filemode
      end
    end

    class RepoCommit < Grape::Entity
      expose :id, :short_id, :title, :author_name, :author_email, :created_at
      expose :safe_message, as: :message
    end

    class RepoCommitStats < Grape::Entity
      expose :additions, :deletions, :total
    end

    class RepoCommitDetail < RepoCommit
      expose :parent_ids, :committed_date, :authored_date
      expose :stats, using: Entities::RepoCommitStats
      expose :status
    end

    class ProjectSnippet < Grape::Entity
      expose :id, :title, :file_name
      expose :author, using: Entities::UserBasic
      expose :updated_at, :created_at

      # TODO (rspeicher): Deprecated; remove in 9.0
      expose(:expires_at) { |snippet| nil }

      expose :web_url do |snippet, options|
        Gitlab::UrlBuilder.build(snippet)
      end
    end

    class ProjectEntity < Grape::Entity
      expose :id, :iid
      expose(:project_id) { |entity| entity.project.id }
      expose :title, :description
      expose :state, :created_at, :updated_at
    end

    class RepoDiff < Grape::Entity
      expose :old_path, :new_path, :a_mode, :b_mode, :diff
      expose :new_file, :renamed_file, :deleted_file
    end

    class Milestone < ProjectEntity
      expose :due_date
      expose :start_date
    end

    class Issue < ProjectEntity
      expose :label_names, as: :labels
      expose :milestone, using: Entities::Milestone
      expose :assignee, :author, using: Entities::UserBasic

      expose :subscribed do |issue, options|
        issue.subscribed?(options[:current_user], options[:project] || issue.project)
      end
      expose :user_notes_count
      expose :upvotes, :downvotes
      expose :due_date
      expose :confidential

      expose :web_url do |issue, options|
        Gitlab::UrlBuilder.build(issue)
      end
    end

    class ExternalIssue < Grape::Entity
      expose :title
      expose :id
    end

    class MergeRequest < ProjectEntity
      expose :target_branch, :source_branch
      expose :upvotes, :downvotes
      expose :author, :assignee, using: Entities::UserBasic
      expose :source_project_id, :target_project_id
      expose :label_names, as: :labels
      expose :work_in_progress?, as: :work_in_progress
      expose :milestone, using: Entities::Milestone
      expose :merge_when_build_succeeds
      expose :merge_status
      expose :diff_head_sha, as: :sha
      expose :merge_commit_sha

      expose :subscribed do |merge_request, options|
        merge_request.subscribed?(options[:current_user], options[:project])
      end

      expose :user_notes_count
      expose :approvals_before_merge
      expose :should_remove_source_branch?, as: :should_remove_source_branch
      expose :force_remove_source_branch?, as: :force_remove_source_branch

      expose :web_url do |merge_request, options|
        Gitlab::UrlBuilder.build(merge_request)
      end
    end

    class MergeRequestChanges < MergeRequest
      expose :diffs, as: :changes, using: Entities::RepoDiff do |compare, _|
        compare.raw_diffs(all_diffs: true).to_a
      end
    end

    class Approvals < Grape::Entity
      expose :user, using: Entities::UserBasic
    end

    class MergeRequestApprovals < ProjectEntity
      expose :merge_status
      expose :approvals_required
      expose :approvals_left
      expose :approvals, as: :approved_by, using: Entities::Approvals

      expose :user_has_approved do |merge_request, options|
        merge_request.has_approved?(options[:current_user])
      end

      expose :user_can_approve do |merge_request, options|
        merge_request.can_approve?(options[:current_user])
      end
    end

    class MergeRequestDiff < Grape::Entity
      expose :id, :head_commit_sha, :base_commit_sha, :start_commit_sha,
        :created_at, :merge_request_id, :state, :real_size
    end

    class MergeRequestDiffFull < MergeRequestDiff
      expose :commits, using: Entities::RepoCommit

      expose :diffs, using: Entities::RepoDiff do |compare, _|
        compare.raw_diffs(all_diffs: true).to_a
      end
    end

    class SSHKey < Grape::Entity
      expose :id, :title, :key, :created_at
    end

    class SSHKeyWithUser < SSHKey
      expose :user, using: Entities::UserFull
    end

    class Note < Grape::Entity
      expose :id
      expose :note, as: :body
      expose :attachment_identifier, as: :attachment
      expose :author, using: Entities::UserBasic
      expose :created_at, :updated_at
      expose :system?, as: :system
      expose :noteable_id, :noteable_type
      # upvote? and downvote? are deprecated, always return false
      expose(:upvote?)    { |note| false }
      expose(:downvote?)  { |note| false }
    end

    class AwardEmoji < Grape::Entity
      expose :id
      expose :name
      expose :user, using: Entities::UserBasic
      expose :created_at, :updated_at
      expose :awardable_id, :awardable_type
    end

    class MRNote < Grape::Entity
      expose :note
      expose :author, using: Entities::UserBasic
    end

    class CommitNote < Grape::Entity
      expose :note
      expose(:path) { |note| note.diff_file.try(:file_path) if note.diff_note? }
      expose(:line) { |note| note.diff_line.try(:new_line) if note.diff_note? }
      expose(:line_type) { |note| note.diff_line.try(:type) if note.diff_note? }
      expose :author, using: Entities::UserBasic
      expose :created_at
    end

    class CommitStatus < Grape::Entity
      expose :id, :sha, :ref, :status, :name, :target_url, :description,
             :created_at, :started_at, :finished_at, :allow_failure
      expose :author, using: Entities::UserBasic
    end

    class Event < Grape::Entity
      expose :title, :project_id, :action_name
      expose :target_id, :target_type, :author_id
      expose :data, :target_title
      expose :created_at
      expose :note, using: Entities::Note, if: ->(event, options) { event.note? }
      expose :author, using: Entities::UserBasic, if: ->(event, options) { event.author }

      expose :author_username do |event, options|
        if event.author
          event.author.username
        end
      end
    end

    class LdapGroup < Grape::Entity
      expose :cn
    end

    class ProjectGroupLink < Grape::Entity
      expose :id, :project_id, :group_id, :group_access, :expires_at
    end

    class Todo < Grape::Entity
      expose :id
      expose :project, using: Entities::BasicProjectDetails
      expose :author, using: Entities::UserBasic
      expose :action_name
      expose :target_type

      expose :target do |todo, options|
        Entities.const_get(todo.target_type).represent(todo.target, options)
      end

      expose :target_url do |todo, options|
        target_type   = todo.target_type.underscore
        target_url    = "namespace_project_#{target_type}_url"
        target_anchor = "note_#{todo.note_id}" if todo.note_id?

        Gitlab::Application.routes.url_helpers.public_send(target_url,
          todo.project.namespace, todo.project, todo.target, anchor: target_anchor)
      end

      expose :body
      expose :state
      expose :created_at
    end

    class Namespace < Grape::Entity
      expose :id, :path, :kind
    end

    class MemberAccess < Grape::Entity
      expose :access_level
      expose :notification_level do |member, options|
        if member.notification_setting
          ::NotificationSetting.levels[member.notification_setting.level]
        end
      end
    end

    class ProjectAccess < MemberAccess
    end

    class GroupAccess < MemberAccess
    end

    class NotificationSetting < Grape::Entity
      expose :level
      expose :events, if: ->(notification_setting, _) { notification_setting.custom? } do
        ::NotificationSetting::EMAIL_EVENTS.each do |event|
          expose event
        end
      end
    end

    class GlobalNotificationSetting < NotificationSetting
      expose :notification_email do |notification_setting, options|
        notification_setting.user.notification_email
      end
    end

    class ProjectService < Grape::Entity
      expose :id, :title, :created_at, :updated_at, :active
      expose :push_events, :issues_events, :merge_requests_events
      expose :tag_push_events, :note_events, :build_events, :pipeline_events
      # Expose serialized properties
      expose :properties do |service, options|
        field_names = service.fields.
          select { |field| options[:include_passwords] || field[:type] != 'password' }.
          map { |field| field[:name] }
        service.properties.slice(*field_names)
      end
    end

    class ProjectWithAccess < Project
      expose :permissions do
        expose :project_access, using: Entities::ProjectAccess do |project, options|
          project.project_members.find_by(user_id: options[:user].id)
        end

        expose :group_access, using: Entities::GroupAccess do |project, options|
          if project.group
            project.group.group_members.find_by(user_id: options[:user].id)
          end
        end
      end
    end

    class LabelBasic < Grape::Entity
      expose :id, :name, :color, :description
    end

    class Label < LabelBasic
      expose :open_issues_count do |label, options|
        label.open_issues_count(options[:current_user])
      end

      expose :closed_issues_count do |label, options|
        label.closed_issues_count(options[:current_user])
      end

      expose :open_merge_requests_count do |label, options|
        label.open_merge_requests_count(options[:current_user])
      end

      expose :priority do |label, options|
        label.priority(options[:project])
      end

      expose :subscribed do |label, options|
        label.subscribed?(options[:current_user], options[:project])
      end
    end

    class List < Grape::Entity
      expose :id
      expose :label, using: Entities::LabelBasic
      expose :position
    end

    class Board < Grape::Entity
      expose :id
      expose :lists, using: Entities::List do |board|
        board.lists.destroyable
      end
    end

    class Compare < Grape::Entity
      expose :commit, using: Entities::RepoCommit do |compare, options|
        Commit.decorate(compare.commits, nil).last
      end

      expose :commits, using: Entities::RepoCommit do |compare, options|
        Commit.decorate(compare.commits, nil)
      end

      expose :diffs, using: Entities::RepoDiff do |compare, options|
        compare.diffs(all_diffs: true).to_a
      end

      expose :compare_timeout do |compare, options|
        compare.diffs.overflow?
      end

      expose :same, as: :compare_same_ref
    end

    class Contributor < Grape::Entity
      expose :name, :email, :commits, :additions, :deletions
    end

    class BroadcastMessage < Grape::Entity
      expose :message, :starts_at, :ends_at, :color, :font
    end

    class ApplicationSetting < Grape::Entity
      expose :id
      expose :default_projects_limit
      expose :signup_enabled
      expose :signin_enabled
      expose :gravatar_enabled
      expose :sign_in_text
      expose :after_sign_up_text
      expose :created_at
      expose :updated_at
      expose :home_page_url
      expose :default_branch_protection
      expose :restricted_visibility_levels
      expose :max_attachment_size
      expose :session_expire_delay
      expose :default_project_visibility
      expose :default_snippet_visibility
      expose :default_group_visibility
      expose :domain_whitelist
      expose :domain_blacklist_enabled
      expose :domain_blacklist
      expose :user_oauth_applications
      expose :after_sign_out_path
      expose :container_registry_token_expire_delay
      expose :repository_storage
      expose :repository_storages
      expose :koding_enabled
      expose :koding_url
    end

    class Release < Grape::Entity
      expose :tag, as: :tag_name
      expose :description
    end

    class RepoTag < Grape::Entity
      expose :name, :message

      expose :commit do |repo_tag, options|
        options[:project].repository.commit(repo_tag.dereferenced_target)
      end

      expose :release, using: Entities::Release do |repo_tag, options|
        options[:project].releases.find_by(tag: repo_tag.name)
      end
    end

    class License < Grape::Entity
      expose :starts_at, :expires_at, :licensee, :add_ons

      expose :user_limit do |license, options|
        license.restricted?(:active_user_count) ? license.restrictions[:active_user_count] : 0
      end

      expose :active_users do |license, options|
        ::User.active.count
      end
    end

    class TriggerRequest < Grape::Entity
      expose :id, :variables
    end

    class Runner < Grape::Entity
      expose :id
      expose :description
      expose :active
      expose :is_shared
      expose :name
    end

    class RunnerDetails < Runner
      expose :tag_list
      expose :run_untagged
      expose :locked
      expose :version, :revision, :platform, :architecture
      expose :contacted_at
      expose :token, if: lambda { |runner, options| options[:current_user].is_admin? || !runner.is_shared? }
      expose :projects, with: Entities::BasicProjectDetails do |runner, options|
        if options[:current_user].is_admin?
          runner.projects
        else
          options[:current_user].authorized_projects.where(id: runner.projects)
        end
      end
    end

    class BuildArtifactFile < Grape::Entity
      expose :filename, :size
    end

    class PipelineBasic < Grape::Entity
      expose :id, :sha, :ref, :status
    end

    class Build < Grape::Entity
      expose :id, :status, :stage, :name, :ref, :tag, :coverage
      expose :created_at, :started_at, :finished_at
      expose :user, with: User
      expose :artifacts_file, using: BuildArtifactFile, if: -> (build, opts) { build.artifacts? }
      expose :commit, with: RepoCommit
      expose :runner, with: Runner
      expose :pipeline, with: PipelineBasic
    end

    class Trigger < Grape::Entity
      expose :token, :created_at, :updated_at, :deleted_at, :last_used
    end

    class Variable < Grape::Entity
      expose :key, :value
    end

    class Pipeline < PipelineBasic
      expose :before_sha, :tag, :yaml_errors

      expose :user, with: Entities::UserBasic
      expose :created_at, :updated_at, :started_at, :finished_at, :committed_at
      expose :duration
      expose :coverage
    end

    class EnvironmentBasic < Grape::Entity
      expose :id, :name, :external_url
    end

    class Environment < EnvironmentBasic
      expose :project, using: Entities::Project
    end

    class Deployment < Grape::Entity
      expose :id, :iid, :ref, :sha, :created_at
      expose :user,        using: Entities::UserBasic
      expose :environment, using: Entities::EnvironmentBasic
      expose :deployable,  using: Entities::Build
    end

    class RepoLicense < Grape::Entity
      expose :key, :name, :nickname
      expose :featured, as: :popular
      expose :url, as: :html_url
      expose(:source_url) { |license| license.meta['source'] }
      expose(:description) { |license| license.meta['description'] }
      expose(:conditions) { |license| license.meta['conditions'] }
      expose(:permissions) { |license| license.meta['permissions'] }
      expose(:limitations) { |license| license.meta['limitations'] }
      expose :content
    end

    class TemplatesList < Grape::Entity
      expose :name
    end

    class Template < Grape::Entity
      expose :name, :content
    end

    class BroadcastMessage < Grape::Entity
      expose :id, :message, :starts_at, :ends_at, :color, :font
      expose :active?, as: :active
    end
  end
end
