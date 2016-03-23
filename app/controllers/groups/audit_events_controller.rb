class Groups::AuditEventsController < Groups::ApplicationController
  before_action :authorize_admin_group!, only: :index
  before_action :group, only: :index

  layout 'group_settings'

  def index
    @events = AuditEvent.where(entity_type: "Group", entity_id: group.id).page(params[:page]).per(20)
  end

  private

  def group
    @group ||= Group.find_by(path: params[:group_id])
  end

  def authorize_admin_group!
    render_404 unless can?(current_user, :admin_group, group)
  end

  def audit_events_params
    params.permit(:group_id)
  end
end
