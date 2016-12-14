class Namespace < ActiveRecord::Base
  acts_as_paranoid

  include CacheMarkdownField
  include Sortable
  include Gitlab::ShellAdapter
  include Gitlab::CurrentSettings
  include Routable

  cache_markdown_field :description, pipeline: :description

  has_many :projects, dependent: :destroy
  has_one :namespace_metrics, dependent: :destroy

  belongs_to :owner, class_name: "User"

  belongs_to :parent, class_name: "Namespace"
  has_many :children, class_name: "Namespace", foreign_key: :parent_id

  validates :owner, presence: true, unless: ->(n) { n.type == "Group" }
  validates :name,
    presence: true,
    uniqueness: true,
    length: { maximum: 255 },
    namespace_name: true

  validates :description, length: { maximum: 255 }
  validates :path,
    presence: true,
    uniqueness: { case_sensitive: false },
    length: { maximum: 255 },
    namespace: true

  delegate :name, to: :owner, allow_nil: true, prefix: true

  after_update :move_dir, if: :path_changed?
  after_commit :refresh_access_of_projects_invited_groups, on: :update, if: -> { previous_changes.key?('share_with_group_lock') }

  # Save the storage paths before the projects are destroyed to use them on after destroy
  before_destroy(prepend: true) { @old_repository_storage_paths = repository_storage_paths }
  after_destroy :rm_dir

  scope :root, -> { where('type IS NULL') }

  delegate :shared_runners_minutes, to: :namespace_metrics, allow_nil: true

  class << self
    def by_path(path)
      find_by('lower(path) = :value', value: path.downcase)
    end

    # Case insensetive search for namespace by path or name
    def find_by_path_or_name(path)
      find_by("lower(path) = :path OR lower(name) = :path", path: path.downcase)
    end

    # Searches for namespaces matching the given query.
    #
    # This method uses ILIKE on PostgreSQL and LIKE on MySQL.
    #
    # query - The search query as a String
    #
    # Returns an ActiveRecord::Relation
    def search(query)
      t = arel_table
      pattern = "%#{query}%"

      where(t[:name].matches(pattern).or(t[:path].matches(pattern)))
    end

    def clean_path(path)
      path = path.dup
      # Get the email username by removing everything after an `@` sign.
      path.gsub!(/@.*\z/,                "")
      # Remove everything that's not in the list of allowed characters.
      path.gsub!(/[^a-zA-Z0-9_\-\.]/,    "")
      # Remove trailing violations ('.atom', '.git', or '.')
      path.gsub!(/(\.atom|\.git|\.)*\z/, "")
      # Remove leading violations ('-')
      path.gsub!(/\A\-+/,                "")

      # Users with the great usernames of "." or ".." would end up with a blank username.
      # Work around that by setting their username to "blank", followed by a counter.
      path = "blank" if path.blank?

      counter = 0
      base = path
      while Namespace.find_by_path_or_name(path)
        counter += 1
        path = "#{base}#{counter}"
      end

      path
    end
  end

  def to_param
    full_path
  end

  def human_name
    owner_name
  end

  def move_dir
    if any_project_has_container_registry_tags?
      raise Exception.new('Namespace cannot be moved, because at least one project has tags in container registry')
    end

    # Move the namespace directory in all storages paths used by member projects
    repository_storage_paths.each do |repository_storage_path|
      # Ensure old directory exists before moving it
      gitlab_shell.add_namespace(repository_storage_path, path_was)

      unless gitlab_shell.mv_namespace(repository_storage_path, path_was, path)
        Rails.logger.error "Exception moving path #{repository_storage_path} from #{path_was} to #{path}"

        # if we cannot move namespace directory we should rollback
        # db changes in order to prevent out of sync between db and fs
        raise Exception.new('namespace directory cannot be moved')
      end
    end

    Gitlab::UploadsTransfer.new.rename_namespace(path_was, path)
    Gitlab::PagesTransfer.new.rename_namespace(path_was, path)

    # If repositories moved successfully we need to
    # send update instructions to users.
    # However we cannot allow rollback since we moved namespace dir
    # So we basically we mute exceptions in next actions
    begin
      send_update_instructions
    rescue
      # Returning false does not rollback after_* transaction but gives
      # us information about failing some of tasks
      false
    end
  end

  def any_project_has_container_registry_tags?
    projects.any?(&:has_container_registry_tags?)
  end

  def send_update_instructions
    projects.each do |project|
      project.send_move_instructions("#{path_was}/#{project.path}")
    end
  end

  def kind
    type == 'Group' ? 'group' : 'user'
  end

  def find_fork_of(project)
    projects.joins(:forked_project_link).find_by('forked_project_links.forked_from_project_id = ?', project.id)
  end

  def lfs_enabled?
    # User namespace will always default to the global setting
    Gitlab.config.lfs.enabled
  end

  def actual_size_limit
    current_application_settings.repository_size_limit
  end

  def full_path
    if parent
      parent.full_path + '/' + path
    else
      path
    end
  end

  private

  def repository_storage_paths
    # We need to get the storage paths for all the projects, even the ones that are
    # pending delete. Unscoping also get rids of the default order, which causes
    # problems with SELECT DISTINCT.
    Project.unscoped do
      projects.select('distinct(repository_storage)').to_a.map(&:repository_storage_path)
    end
  end

  def rm_dir
    # Remove the namespace directory in all storages paths used by member projects
    @old_repository_storage_paths.each do |repository_storage_path|
      # Move namespace directory into trash.
      # We will remove it later async
      new_path = "#{path}+#{id}+deleted"

      if gitlab_shell.mv_namespace(repository_storage_path, path, new_path)
        message = "Namespace directory \"#{path}\" moved to \"#{new_path}\""
        Gitlab::AppLogger.info message

        # Remove namespace directroy async with delay so
        # GitLab has time to remove all projects first
        GitlabShellWorker.perform_in(5.minutes, :rm_namespace, repository_storage_path, new_path)
      end
    end
  end

  def refresh_access_of_projects_invited_groups
    Group.
      joins(project_group_links: :project).
      where(projects: { namespace_id: id }).
      find_each(&:refresh_members_authorized_projects)
  end

<<<<<<< HEAD
  def full_path_changed?
    path_changed? || parent_id_changed?
=======
  def shared_runners_minutes_limit
    read_attribute(:shared_runners_minutes_limit) ||
      current_application_settings.shared_runners_minutes
  end

  def shared_runners_minutes_limit_enabled?
    shared_runners_minutes_limit.nonzero?
  end

  def shared_runners_minutes_used?
    shared_runners_enabled? &&
      shared_runners_minutes_limit_enabled? &&
      shared_runners_minutes.to_i < shared_runners_minutes_limit
>>>>>>> Add namespace_metrics and count number of build minutes on namespace basis
  end
end
