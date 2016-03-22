class Groups::AnalyticsController < Groups::ApplicationController
  before_action :group_projects

  def show
    @users = @group.users
    @start_date = params[:start_date] || Date.today - 1.week
    @events = Event.contributions.
      in_projects(@projects).
      where("created_at > ?", @start_date)

    @stats = {}

    @stats[:merge_requests] = @users.map do |user|
      @events.merge_requests.created.where(author_id: user).count
    end

    @stats[:issues] = @users.map do |user|
      @events.issues.closed.where(author_id: user).count
    end

    @stats[:push] = @users.map do |user|
      @events.code_push.where(author_id: user).count
    end
  end
end
