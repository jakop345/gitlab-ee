module NotificationsHelper
  include IconsHelper

  def notification_icon_class(level)
    case level.to_sym
    when :disabled
      'microphone-slash'
    when :participating
      'volume-up'
    when :watch
      'eye'
    when :mention
      'at'
    when :global
      'globe'
    end
  end

  def notification_icon(level, text = nil)
    icon("#{notification_icon_class(level)} fw", text: text)
  end

  def notification_title(level)
    case level.to_sym
    when :participating
      'Participate'
    when :mention
      'On mention'
    else
      level.to_s.titlecase
    end
  end

  def notification_description(level)
    case level.to_sym
    when :participating
      'You will only receive notifications from related resources'
    when :mention
      'You will receive notifications only for comments in which you were @mentioned'
    when :watch
      'You will receive notifications for any activity'
    when :disabled
      'You will not get any notifications via email'
    when :global
      'Use your global notification setting'
    end
  end

  def notification_list_item(level, setting)
    title = notification_title(level)

    data = {
      notification_level: level,
      notification_title: title
    }

    content_tag(:li, role: "menuitem") do
      link_to '#', class: "update-notification #{('is-active' if setting.level == level)}", data: data do
        link_output = content_tag(:strong, title, class: 'dropdown-menu-inner-title')
        link_output << content_tag(:span, notification_description(level), class: 'dropdown-menu-inner-content')
      end
    end
  end
end
