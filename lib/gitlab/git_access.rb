# Check a user's access to perform a git action. All public methods in this
# class return an instance of `GitlabAccessStatus`
module Gitlab
  class GitAccess
    include PathLocksHelper
    UnauthorizedError = Class.new(StandardError)

    ERROR_MESSAGES = {
      upload: 'You are not allowed to upload code for this project.',
      download: 'You are not allowed to download code from this project.',
      deploy_key: 'Deploy keys are not allowed to push code.',
      no_repo: 'A repository for this project does not exist yet.'
    }

    DOWNLOAD_COMMANDS = %w{ git-upload-pack git-upload-archive }
    PUSH_COMMANDS = %w{ git-receive-pack }
    GIT_ANNEX_COMMANDS = %w{ git-annex-shell }
    ALL_COMMANDS = DOWNLOAD_COMMANDS + PUSH_COMMANDS + GIT_ANNEX_COMMANDS

    attr_reader :actor, :project, :protocol, :user_access, :authentication_abilities

    def initialize(actor, project, protocol, authentication_abilities:, env: {})
      @actor    = actor
      @project  = project
      @protocol = protocol
      @authentication_abilities = authentication_abilities
      @user_access = UserAccess.new(user, project: project)
      @env = env
    end

    def check(cmd, changes)
      check_protocol!
      check_active_user!
      check_project_accessibility!
      check_command_existence!(cmd)

      check_geo_license!

      case cmd
      when *DOWNLOAD_COMMANDS
        download_access_check
      when *PUSH_COMMANDS
        push_access_check(changes)
      when *GIT_ANNEX_COMMANDS
        git_annex_access_check(project, changes)
      end

      build_status_object(true)
    rescue UnauthorizedError => ex
      build_status_object(false, ex.message)
    end

    def download_access_check
      if user
        user_download_access_check
      elsif deploy_key.nil? && geo_node_key.nil? && !guest_can_downlod_code?
        raise UnauthorizedError, ERROR_MESSAGES[:download]
      end
    end

    def push_access_check(changes)
      if project.repository_read_only?
        raise UnauthorizedError, 'The repository is temporarily read-only. Please try again later.'
      end

      if Gitlab::Geo.secondary?
        raise UnauthorizedError, "You can't push code on a secondary GitLab Geo node."
      end

      return if git_annex_branch_sync?(changes)

      if user
        user_push_access_check(changes)
      else
        raise UnauthorizedError, ERROR_MESSAGES[deploy_key ? :deploy_key : :upload]
      end
    end

    def guest_can_downlod_code?
      Guest.can?(:download_code, project)
    end

    def user_download_access_check
      unless user_can_download_code? || build_can_download_code?
        raise UnauthorizedError, ERROR_MESSAGES[:download]
      end
    end

    def user_can_download_code?
      authentication_abilities.include?(:download_code) && user_access.can_do_action?(:download_code)
    end

    def build_can_download_code?
      authentication_abilities.include?(:build_download_code) && user_access.can_do_action?(:build_download_code)
    end

    def user_push_access_check(changes)
      unless authentication_abilities.include?(:push_code)
        raise UnauthorizedError, ERROR_MESSAGES[:upload]
      end

      if changes.blank?
        return # Allow access.
      end

      unless project.repository.exists?
        raise UnauthorizedError, ERROR_MESSAGES[:no_repo]
      end

      if project.above_size_limit?
        raise UnauthorizedError, Gitlab::RepositorySizeError.new(project).push_error
      end

      if ::License.block_changes?
        message = ::LicenseHelper.license_message(signed_in: true, is_admin: (user && user.is_admin?))
        raise UnauthorizedError, message
      end

      changes_list = Gitlab::ChangesList.new(changes)

      push_size_in_bytes = 0

      # Iterate over all changes to find if user allowed all of them to be applied
      changes_list.each do |change|
        status = change_access_check(change)
        unless status.allowed?
          # If user does not have access to make at least one change - cancel all push
          raise UnauthorizedError, status.message
        end

        if project.size_limit_enabled?
          push_size_in_bytes += EE::Gitlab::Deltas.delta_size_check(change, project.repository)
        end
      end

      if project.changes_will_exceed_size_limit?(push_size_in_bytes.to_mb)
        raise UnauthorizedError, Gitlab::RepositorySizeError.new(project).new_changes_error
      end
    end

    def change_access_check(change)
      Checks::ChangeAccess.new(change, user_access: user_access, project: project, env: @env).exec
    end

    def protocol_allowed?
      Gitlab::ProtocolAccess.allowed?(protocol)
    end

    private

    def check_protocol!
      unless protocol_allowed?
        raise UnauthorizedError, "Git access over #{protocol.upcase} is not allowed"
      end
    end

    def check_active_user!
      if user && !user_access.allowed?
        raise UnauthorizedError, "Your account has been blocked."
      end
    end

    def check_project_accessibility!
      if project.blank? || !can_read_project?
        raise UnauthorizedError, 'The project you were looking for could not be found.'
      end
    end

    def check_command_existence!(cmd)
      unless ALL_COMMANDS.include?(cmd)
        raise UnauthorizedError, "The command you're trying to execute is not allowed."
      end
    end

    def check_geo_license!
      if Gitlab::Geo.secondary? && !Gitlab::Geo.license_allows?
        raise UnauthorizedError, 'Your current license does not have GitLab Geo add-on enabled.'
      end
    end

    def matching_merge_request?(newrev, branch_name)
      Checks::MatchingMergeRequest.new(newrev, branch_name, project).match?
    end

    def protected_branch_action(oldrev, newrev, branch_name)
      # we dont allow force push to protected branch
      if forced_push?(oldrev, newrev)
        :force_push_code_to_protected_branches
      elsif Gitlab::Git.blank_ref?(newrev)
        # and we dont allow remove of protected branch
        :remove_protected_branches
      elsif matching_merge_request?(newrev, branch_name) && project.developers_can_merge_to_protected_branch?(branch_name)
        :push_code
      elsif project.developers_can_push_to_protected_branch?(branch_name)
        :push_code
      else
        :push_code_to_protected_branches
      end
    end

    def protected_tag?(tag_name)
      project.repository.tag_exists?(tag_name)
    end

    def deploy_key
      actor if actor.is_a?(DeployKey)
    end

    def geo_node_key
      actor if actor.is_a?(GeoNodeKey)
    end

    def deploy_key_can_read_project?
      if deploy_key
        return true if project.public?
        deploy_key.projects.include?(project)
      else
        false
      end
    end

    def can_read_project?
      if user
        user_access.can_read_project?
      elsif deploy_key
        deploy_key_can_read_project?
      elsif geo_node_key
        true
      else
        Guest.can?(:read_project, project)
      end
    end

    protected

    def user
      return @user if defined?(@user)

      @user =
        case actor
        when User
          actor
        when DeployKey
          nil
        when GeoNodeKey
          nil
        when Key
          actor.user
        end
    end

    def build_status_object(status, message = '')
      Gitlab::GitAccessStatus.new(status, message)
    end

    def git_annex_access_check(project, changes)
      raise UnauthorizedError, "git-annex is disabled" unless Gitlab.config.gitlab_shell.git_annex_enabled

      unless user && user_access.allowed?
        raise UnauthorizedError, "You don't have access"
      end

      unless project.repository.exists?
        raise UnauthorizedError, "Repository does not exist"
      end

      if Gitlab::Geo.enabled? && Gitlab::Geo.secondary?
        raise UnauthorizedError, "You can't use git-annex with a secondary GitLab Geo node."
      end

      unless user.can?(:push_code, project)
        raise UnauthorizedError, "You don't have permission"
      end
    end

    def git_annex_branch_sync?(changes)
      return false unless Gitlab.config.gitlab_shell.git_annex_enabled
      return false if changes.blank?

      changes = changes.lines if changes.kind_of?(String)

      # Iterate over all changes to find if user allowed all of them to be applied
      # 0000000000000000000000000000000000000000 3073696294ddd52e9e6b6fc3f429109cac24626f refs/heads/synced/git-annex
      # 0000000000000000000000000000000000000000 65be9df0e995d36977e6d76fc5801b7145ce19c9 refs/heads/synced/master
      changes.map(&:strip).reject(&:blank?).each do |change|
        unless change.end_with?("refs/heads/synced/git-annex") || change.include?("refs/heads/synced/")
          return false
        end
      end

      true
    end

    def commit_from_annex_sync?(commit_message)
      return false unless Gitlab.config.gitlab_shell.git_annex_enabled

      # Commit message starting with <git-annex in > so avoid push rules on this
      commit_message.start_with?('git-annex in')
    end

    def old_commit?(commit)
      commit.refs(project.repository).any?
    end
  end
end
