# The database stores locked paths as following:
# 'app/models/project.rb' or 'lib/gitlab'
# To determine that 'lib/gitlab/some_class.rb' is locked we need to generate
# tokens for every requested paths and check every token whether it exist in locked paths or not.
# So for 'lib/gitlab/some_class.rb' path we would need to search next paths:
# 'lib', 'lib/gitlab' and 'lib/gitlab/some_class.rb'
# It's also desirable to use cache or memoization for common paths like 'lib' 'lib/gitlab', 'app', etc.

class Gitlab::LockedPathMatcher
  def initialize(project)
    @project = project
    @non_locked_paths = []
  end

  def get_lock_info(path)
    tokenizer(path).each do |token|
      if lock = find_lock(token)
        return lock
      end
    end

    false
  end

  private

  # This returns hierarchy tokens for path
  # app/models/project.rb => ['app', 'app/models', 'app/models/project.rb']
  def tokenizer(path)
    tokens = []

    path.split('/').each do |fragment|
      last_token = tokens.last

      if last_token
        tokens << "#{last_token}/#{fragment}"
      else
        tokens << fragment
      end
    end

    tokens
  end

  # TODO: Fix case insensitiveness
  def find_lock(token)
    if @non_locked_paths.include? token
      return false
    end

    lock = @project.path_locks.find_by(path: token)

    unless lock
      @non_locked_paths << token
    end

    lock
  end
end