module Users
  class ActivityService
    def initialize(author, activity)
      @author = author.respond_to?(:user) ? author.user : author
      @activity = activity
    end

    def execute
      return unless current_application_settings.user_activity_enabled && has_author?

      record_activity
    end

    private

    def has_author?
      @author && @author.is_a?(User)
    end

    def record_activity
      user_activity.touch

      Rails.logger.debug("Recorded activity: #{@activity} for User ID: #{@author.id} (username: #{@author.username}")
    end

    def user_activity
      UserActivity.find_or_initialize_by(user: @author)
    end
  end
end
