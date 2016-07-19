class MergeRequestDiff < ActiveRecord::Base
  include Sortable
  include Importable
  include EncodingHelper

  # Prevent store of diff if commits amount more then 500
  COMMITS_SAFE_SIZE = 100

  belongs_to :merge_request

  delegate :source_branch_sha, :target_branch_sha, :target_branch, :source_branch, to: :merge_request, prefix: nil

  state_machine :state, initial: :empty do
    state :collected
    state :overflow
    # Deprecated states: these are no longer used but these values may still occur
    # in the database.
    state :timeout
    state :overflow_commits_safe_size
    state :overflow_diff_files_limit
    state :overflow_diff_lines_limit
  end

  serialize :st_commits
  serialize :st_diffs

  after_create :reload_content, unless: :importing?
  after_save :keep_around_commits, unless: :importing?

  def reload_content
    reload_commits
    reload_diffs
  end

  def size
    real_size.presence || diffs.size
  end

  def diffs(options={})
    if options[:ignore_whitespace_change]
      @diffs_no_whitespace ||= begin
        compare = Gitlab::Git::Compare.new(
          repository.raw_repository,
          self.start_commit_sha || self.target_branch_sha,
          self.head_commit_sha || self.source_branch_sha,
        )
        compare.diffs(options)
      end
    else
      @diffs ||= {}
      @diffs[options] ||= load_diffs(st_diffs, options)
    end
  end

  def commits
    @commits ||= load_commits(st_commits || [])
  end

  def last_commit
    commits.first
  end

  def first_commit
    commits.last
  end

  def base_commit
    return unless self.base_commit_sha

    project.commit(self.base_commit_sha)
  end

  def start_commit
    return unless self.start_commit_sha

    project.commit(self.start_commit_sha)
  end

  def head_commit
    return last_commit unless self.head_commit_sha

    project.commit(self.head_commit_sha)
  end

  def compare
    @compare ||=
      begin
        # Update ref for merge request
        merge_request.fetch_ref

        Gitlab::Git::Compare.new(
          repository.raw_repository,
          self.target_branch_sha,
          self.source_branch_sha
        )
      end
  end

  private

  # Collect array of Git::Commit objects
  # between target and source branches
  def unmerged_commits
    commits = compare.commits

    if commits.present?
      commits = Commit.decorate(commits, merge_request.source_project).reverse
    end

    commits
  end

  def dump_commits(commits)
    commits.map(&:to_hash)
  end

  def load_commits(array)
    array.map { |hash| Commit.new(Gitlab::Git::Commit.new(hash), merge_request.source_project) }
  end

  # Reload all commits related to current merge request from repo
  # and save it as array of hashes in st_commits db field
  def reload_commits
    new_attributes = {}

    commit_objects = unmerged_commits

    if commit_objects.present?
      new_attributes[:st_commits] = dump_commits(commit_objects)
    end

    update_columns_serialized(new_attributes)
  end

  # Collect array of Git::Diff objects
  # between target and source branches
  def unmerged_diffs
    compare.diffs(Commit.max_diff_options)
  end

  def dump_diffs(diffs)
    if diffs.respond_to?(:map)
      diffs.map(&:to_hash)
    end
  end

  def load_diffs(raw, options)
    if raw.respond_to?(:each)
      if paths = options[:paths]
        raw = raw.select do |diff|
          paths.include?(diff[:old_path]) || paths.include?(diff[:new_path])
        end
      end

      Gitlab::Git::DiffCollection.new(raw, options)
    else
      Gitlab::Git::DiffCollection.new([])
    end
  end

  # Reload diffs between branches related to current merge request from repo
  # and save it as array of hashes in st_diffs db field
  def reload_diffs
    new_attributes = {}
    new_diffs = []

    if commits.size.zero?
      new_attributes[:state] = :empty
    else
      diff_collection = unmerged_diffs

      if diff_collection.overflow?
        # Set our state to 'overflow' to make the #empty? and #collected?
        # methods (generated by StateMachine) return false.
        new_attributes[:state] = :overflow
      end

      new_attributes[:real_size] = diff_collection.real_size

      if diff_collection.any?
        new_diffs = dump_diffs(diff_collection)
        new_attributes[:state] = :collected
      end
    end

    new_attributes[:st_diffs] = new_diffs

    new_attributes[:start_commit_sha] = self.target_branch_sha
    new_attributes[:head_commit_sha] = self.source_branch_sha
    new_attributes[:base_commit_sha] = branch_base_sha

    update_columns_serialized(new_attributes)

    keep_around_commits
  end

  def project
    merge_request.target_project
  end

  def repository
    project.repository
  end

  def branch_base_commit
    return unless self.source_branch_sha && self.target_branch_sha

    project.merge_base_commit(self.source_branch_sha, self.target_branch_sha)
  end

  def branch_base_sha
    branch_base_commit.try(:sha)
  end

  def utf8_st_diffs
    st_diffs.map do |diff|
      diff.each do |k, v|
        diff[k] = encode_utf8(v) if v.respond_to?(:encoding)
      end
    end
  end

  #
  # #save or #update_attributes providing changes on serialized attributes do a lot of
  # serialization and deserialization calls resulting in bad performance.
  # Using #update_columns solves the problem with just one YAML.dump per serialized attribute that we provide.
  # As a tradeoff we need to reload the current instance to properly manage time objects on those serialized
  # attributes. So to keep the same behaviour as the attribute assignment we reload the instance.
  # The difference is in the usage of
  # #write_attribute= (#update_attributes) and #raw_write_attribute= (#update_columns)
  #
  # Ex:
  #
  #   new_attributes[:st_commits].first.slice(:committed_date)
  #   => {:committed_date=>2014-02-27 11:01:38 +0200}
  #   YAML.load(YAML.dump(new_attributes[:st_commits].first.slice(:committed_date)))
  #   => {:committed_date=>2014-02-27 10:01:38 +0100}
  #
  def update_columns_serialized(new_attributes)
    return unless new_attributes.any?

    update_columns(new_attributes.merge(updated_at: current_time_from_proper_timezone))
    reload
  end

  def keep_around_commits
    repository.keep_around(target_branch_sha)
    repository.keep_around(source_branch_sha)
    repository.keep_around(branch_base_sha)
  end
end
