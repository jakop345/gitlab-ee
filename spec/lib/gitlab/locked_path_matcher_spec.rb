require 'spec_helper'

describe Gitlab::LockedPathMatcher, lib: true do
  let(:project) { create :empty_project }
  let(:user) { create :user }
  let(:matcher) { Gitlab::LockedPathMatcher.new(project) }

  it "returns correct lock information" do
    lock1 = create :path_lock, project: project, path: 'app'
    lock2 = create :path_lock, project: project, path: 'lib/gitlab/repo.rb'

    expect(matcher.get_lock_info('app')).to eq(lock1)
    expect(matcher.get_lock_info('app/models/project.rb')).to eq(lock1)
    expect(matcher.get_lock_info('lib')).to be_falsey
    expect(matcher.get_lock_info('lib/gitlab/repo.rb')).to eq(lock2)
  end
end
