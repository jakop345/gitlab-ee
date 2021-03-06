class ProjectsController < Projects::ApplicationController
  include IssuableCollections
  include ExtractsPath

  before_action :authenticate_user!, except: [:index, :show, :activity, :refs]
  before_action :project, except: [:index, :new, :create]
  before_action :repository, except: [:index, :new, :create]
  before_action :assign_ref_vars, only: [:show], if: :repo_exists?
  before_action :assign_tree_vars, only: [:show], if: [:repo_exists?, :project_view_files?]

  # Authorize
  before_action :authorize_admin_project!, only: [:edit, :update, :housekeeping, :download_export, :export, :remove_export, :generate_new_export]
  before_action :event_filter, only: [:show, :activity]

  layout :determine_layout

  def index
    redirect_to(current_user ? root_path : explore_root_path)
  end

  def new
    @project = Project.new
  end

  def edit
    render 'edit'
  end

  def create
    @project = ::Projects::CreateService.new(current_user, project_params).execute

    if @project.saved?
      cookies[:issue_board_welcome_hidden] = { path: project_path(@project), value: nil, expires: Time.at(0) }

      redirect_to(
        project_path(@project),
        notice: "Project '#{@project.name}' was successfully created."
      )
    else
      render 'new'
    end
  end

  def update
    status = ::Projects::UpdateService.new(@project, current_user, project_params).execute

    # Refresh the repo in case anything changed
    @repository = project.repository

    respond_to do |format|
      if status
        flash[:notice] = "Project '#{@project.name}' was successfully updated."
        format.html do
          redirect_to(
            edit_project_path(@project),
            notice: "Project '#{@project.name}' was successfully updated."
          )
        end
      else
        format.html { render 'edit' }
      end

      format.js
    end
  end

  def transfer
    return access_denied! unless can?(current_user, :change_namespace, @project)

    namespace = Namespace.find_by(id: params[:new_namespace_id])
    ::Projects::TransferService.new(project, current_user).execute(namespace)

    if @project.errors[:new_namespace].present?
      flash[:alert] = @project.errors[:new_namespace].first
    end
  end

  def remove_fork
    return access_denied! unless can?(current_user, :remove_fork_project, @project)

    if ::Projects::UnlinkForkService.new(@project, current_user).execute
      flash[:notice] = 'The fork relationship has been removed.'
    end
  end

  def activity
    respond_to do |format|
      format.html
      format.json do
        load_events
        pager_json('events/_events', @events.count)
      end
    end
  end

  def show
    # If we're importing while we do have a repository, we're simply updating the mirror.
    if @project.import_in_progress? && !@project.updating_mirror?
      redirect_to namespace_project_import_path(@project.namespace, @project)
      return
    end

    if @project.pending_delete?
      flash[:alert] = "Project #{@project.name} queued for deletion."
    end

    respond_to do |format|
      format.html do
        @notification_setting = current_user.notification_settings_for(@project) if current_user
        render_landing_page
      end

      format.atom do
        load_events
        render layout: false
      end
    end
  end

  def destroy
    return access_denied! unless can?(current_user, :remove_project, @project)

    ::Projects::DestroyService.new(@project, current_user, {}).async_execute
    flash[:alert] = "Project '#{@project.name}' will be deleted."

    redirect_to dashboard_projects_path
  rescue Projects::DestroyService::DestroyError => ex
    redirect_to edit_project_path(@project), alert: ex.message
  end

  def autocomplete_sources
    noteable =
      case params[:type]
      when 'Issue'
        IssuesFinder.new(current_user, project_id: @project.id).
          execute.find_by(iid: params[:type_id])
      when 'MergeRequest'
        MergeRequestsFinder.new(current_user, project_id: @project.id).
          execute.find_by(iid: params[:type_id])
      when 'Commit'
        @project.commit(params[:type_id])
      else
        nil
      end

    autocomplete = ::Projects::AutocompleteService.new(@project, current_user)
    participants = ::Projects::ParticipantsService.new(@project, current_user).execute(noteable)

    @suggestions = {
      emojis: Gitlab::AwardEmoji.urls,
      issues: autocomplete.issues,
      milestones: autocomplete.milestones,
      mergerequests: autocomplete.merge_requests,
      labels: autocomplete.labels,
      members: participants,
      commands: autocomplete.commands(noteable, params[:type])
    }

    respond_to do |format|
      format.json { render json: @suggestions }
    end
  end

  def new_issue_address
    return render_404 unless Gitlab::IncomingEmail.supports_issue_creation?

    current_user.reset_incoming_email_token!
    render json: { new_issue_address: @project.new_issue_address(current_user) }
  end

  def archive
    return access_denied! unless can?(current_user, :archive_project, @project)

    @project.archive!

    respond_to do |format|
      format.html { redirect_to project_path(@project) }
    end
  end

  def unarchive
    return access_denied! unless can?(current_user, :archive_project, @project)

    @project.unarchive!

    respond_to do |format|
      format.html { redirect_to project_path(@project) }
    end
  end

  def housekeeping
    ::Projects::HousekeepingService.new(@project).execute

    redirect_to(
      project_path(@project),
      notice: "Housekeeping successfully started"
    )
  rescue ::Projects::HousekeepingService::LeaseTaken => ex
    redirect_to(
      edit_project_path(@project),
      alert: ex.to_s
    )
  end

  def export
    @project.add_export_job(current_user: current_user)

    redirect_to(
      edit_project_path(@project),
      notice: "Project export started. A download link will be sent by email."
    )
  end

  def download_export
    export_project_path = @project.export_project_path

    if export_project_path
      send_file export_project_path, disposition: 'attachment'
    else
      redirect_to(
        edit_project_path(@project),
        alert: "Project export link has expired. Please generate a new export from your project settings."
      )
    end
  end

  def remove_export
    if @project.remove_exports
      flash[:notice] = "Project export has been deleted."
    else
      flash[:alert] = "Project export could not be deleted."
    end
    redirect_to(edit_project_path(@project))
  end

  def generate_new_export
    if @project.remove_exports
      export
    else
      redirect_to(
        edit_project_path(@project),
        alert: "Project export could not be deleted."
      )
    end
  end

  def toggle_star
    current_user.toggle_star(@project)
    @project.reload

    render json: {
      star_count: @project.star_count
    }
  end

  def preview_markdown
    text = params[:text]

    ext = Gitlab::ReferenceExtractor.new(@project, current_user)
    ext.analyze(text, author: current_user)

    render json: {
      body:       view_context.markdown(text),
      references: {
        users: ext.users.map(&:username)
      }
    }
  end

  def refs
    options = {
      'Branches' => @repository.branch_names,
    }

    unless @repository.tag_count.zero?
      options['Tags'] = VersionSorter.rsort(@repository.tag_names)
    end

    # If reference is commit id - we should add it to branch/tag selectbox
    ref = Addressable::URI.unescape(params[:ref])
    if ref && options.flatten(2).exclude?(ref) && ref =~ /\A[0-9a-zA-Z]{6,52}\z/
      options['Commits'] = [ref]
    end

    render json: options.to_json
  end

  private

  # Render project landing depending of which features are available
  # So if page is not availble in the list it renders the next page
  #
  # pages list order: repository readme, wiki home, issues list, customize workflow
  def render_landing_page
    if @project.feature_available?(:repository, current_user)
      return render 'projects/no_repo' unless @project.repository_exists?
      render 'projects/empty' if @project.empty_repo?
    else
      if @project.wiki_enabled?
        @project_wiki = @project.wiki
        @wiki_home = @project_wiki.find_page('home', params[:version_id])
      elsif @project.feature_available?(:issues, current_user)
        @issues = issues_collection
        @issues = @issues.page(params[:page])
      end

      render :show
    end
  end

  def determine_layout
    if [:new, :create].include?(action_name.to_sym)
      'application'
    elsif [:edit, :update].include?(action_name.to_sym)
      'project_settings'
    else
      'project'
    end
  end

  def load_events
    @events = @project.events.recent
    @events = event_filter.apply_filter(@events).with_associations
    limit = (params[:limit] || 20).to_i
    @events = @events.limit(limit).offset(params[:offset] || 0)
  end

  def project_params
    params.require(:project)
      .permit(project_params_ce << project_params_ee)
  end

  def project_params_ce
    [
      :avatar,
      :build_allow_git_fetch,
      :build_coverage_regex,
      :build_timeout_in_minutes,
      :container_registry_enabled,
      :default_branch,
      :description,
      :import_url,
      :issues_tracker,
      :issues_tracker_id,
      :last_activity_at,
      :lfs_enabled,
      :name,
      :namespace_id,
      :only_allow_merge_if_all_discussions_are_resolved,
      :only_allow_merge_if_build_succeeds,
      :path,
      :public_builds,
      :request_access_enabled,
      :runners_token,
      :tag_list,
      :visibility_level,

      project_feature_attributes: %i[
        builds_access_level
        issues_access_level
        merge_requests_access_level
        repository_access_level
        snippets_access_level
        wiki_access_level
      ]
    ]
  end

  def project_params_ee
    %i[
      approvals_before_merge
      approver_group_ids
      approver_ids
      issues_template
      merge_method
      merge_requests_template
      mirror
      mirror_trigger_builds
      mirror_user_id
      repository_size_limit
      reset_approvals_on_push
    ]
  end

  def repo_exists?
    project.repository_exists? && !project.empty_repo? && project.repo

  rescue Gitlab::Git::Repository::NoRepository
    project.repository.expire_exists_cache

    false
  end

  def project_view_files?
    current_user && current_user.project_view == 'files'
  end

  # Override extract_ref from ExtractsPath, which returns the branch and file path
  # for the blob/tree, which in this case is just the root of the default branch.
  # This way we avoid to access the repository.ref_names.
  def extract_ref(_id)
    [get_id, '']
  end

  # Override get_id from ExtractsPath in this case is just the root of the default branch.
  def get_id
    project.repository.root_ref
  end

  # ExtractsPath will set @id = project.path on the show route, but it has to be the
  # branch name for the tree view to work correctly.
  def assign_tree_vars
    @id = get_id
    tree
  end
end
