class Projects::ServicesController < Projects::ApplicationController
  ALLOWED_PARAMS = [
    :active,
    :add_pusher,
    :api_key,
    :api_url,
    :api_version,
    :bamboo_url,
    :build_events,
    :build_key,
    :build_type,
    :channel,
    :channels,
    :color,
    :colorize_messages,
    :default_irc_uri,
    :description,
    :device,
    :disable_diffs,
    :drone_url,
    :enable_ssl_verification,
    :external_wiki_url,
    :issues_events,
    :issues_url,
    :jira_issue_transition_id,
    :merge_requests_events,
    :new_issue_url,
    :note_events,
    :notify,
    :notify_only_broken_builds,
    :password,
    :priority,
    :project_url,
    :push_events,
    :recipients,
    :restrict_to_branch,
    :room,
    :send_from_committer_email,
    :server,
    :server_host,
    :server_port,
    :sound,
    :subdomain,
    :tag_push_events,
    :teamcity_url,
    :title,
    :token,
    :type,
    :user_key,
    :username,
    :webhook,
    :wiki_page_events,

    # EE options
    :jenkins_url,
    :jira_issue_transition_id,
    :multiproject_enabled,
    :pass_unstable,
    :project_name
  ]

  # Parameters to ignore if no value is specified
  FILTER_BLANK_PARAMS = [:password]

  # Authorize
  before_action :authorize_admin_project!
  before_action :service, only: [:edit, :update, :test]

  respond_to :html

  layout "project_settings"

  def index
    @project.build_missing_services
    @services = @project.services.visible.reload
  end

  def edit
  end

  def update
    if @service.update_attributes(service_params)
      redirect_to(
        edit_namespace_project_service_path(@project.namespace, @project,
                                            @service.to_param, notice:
                                            'Successfully updated.')
      )
    else
      render 'edit'
    end
  end

  def test
    data = Gitlab::PushDataBuilder.build_sample(project, current_user)
    outcome = @service.test(data)
    if outcome[:success]
      message = { notice: 'We sent a request to the provided URL' }
    else
      error_message = "We tried to send a request to the provided URL but an error occurred"
      error_message << ": #{outcome[:result]}" if outcome[:result].present?
      message = { alert: error_message }
    end

    redirect_back_or_default(options: message)
  end

  private

  def service
    @service ||= @project.services.find { |service| service.to_param == params[:id] }
  end

  def service_params
    service_params = params.require(:service).permit(ALLOWED_PARAMS)
    FILTER_BLANK_PARAMS.each do |param|
      service_params.delete(param) if service_params[param].blank?
    end
    service_params
  end
end
