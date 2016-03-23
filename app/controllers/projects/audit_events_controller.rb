class Projects::AuditEventsController < Projects::ApplicationController
  before_action :authorize_admin_project!, only: :index
  before_action :project, only: :index

  layout 'project_settings'

  def index
    @events = AuditEvent.where(entity_type: "Project", entity_id: project.id).page(params[:page]).per(20)
  end

  private

  def audit_events_params
    params.permit(:project_id)
  end
end
