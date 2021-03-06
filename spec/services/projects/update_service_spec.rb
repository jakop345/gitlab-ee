require 'spec_helper'

describe Projects::UpdateService, services: true do
  describe :update_by_user do
    before do
      @user = create :user
      @admin = create :user, admin: true
      @project = create :project, creator_id: @user.id, namespace: @user.namespace
      @opts = {}
    end

    context 'is private when updated to private' do
      before do
        @created_private = @project.private?

        @opts.merge!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
        update_project(@project, @user, @opts)
      end

      it { expect(@created_private).to be_truthy }
      it { expect(@project.private?).to be_truthy }
    end

    context 'is internal when updated to internal' do
      before do
        @created_private = @project.private?

        @opts.merge!(visibility_level: Gitlab::VisibilityLevel::INTERNAL)
        update_project(@project, @user, @opts)
      end

      it { expect(@created_private).to be_truthy }
      it { expect(@project.internal?).to be_truthy }
    end

    context 'is public when updated to public' do
      before do
        @created_private = @project.private?

        @opts.merge!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
        update_project(@project, @user, @opts)
      end

      it { expect(@created_private).to be_truthy }
      it { expect(@project.public?).to be_truthy }
    end

    context 'respect configured visibility restrictions setting' do
      before(:each) do
        stub_application_setting(restricted_visibility_levels: [Gitlab::VisibilityLevel::PUBLIC])
      end

      context 'is private when updated to private' do
        before do
          @created_private = @project.private?

          @opts.merge!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
          update_project(@project, @user, @opts)
        end

        it { expect(@created_private).to be_truthy }
        it { expect(@project.private?).to be_truthy }
      end

      context 'is internal when updated to internal' do
        before do
          @created_private = @project.private?

          @opts.merge!(visibility_level: Gitlab::VisibilityLevel::INTERNAL)
          update_project(@project, @user, @opts)
        end

        it { expect(@created_private).to be_truthy }
        it { expect(@project.internal?).to be_truthy }
      end

      context 'is private when updated to public' do
        before do
          @created_private = @project.private?

          @opts.merge!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
          update_project(@project, @user, @opts)
        end

        it { expect(@created_private).to be_truthy }
        it { expect(@project.private?).to be_truthy }
      end

      context 'is public when updated to public by admin' do
        before do
          @created_private = @project.private?

          @opts.merge!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
          update_project(@project, @admin, @opts)
        end

        it { expect(@created_private).to be_truthy }
        it { expect(@project.public?).to be_truthy }
      end
    end
  end

  describe :visibility_level do
    let(:user) { create :user, admin: true }
    let(:project) { create(:project, :internal) }
    let(:forked_project) { create(:forked_project_with_submodules, :internal) }
    let(:opts) { {} }

    before do
      forked_project.build_forked_project_link(forked_to_project_id: forked_project.id, forked_from_project_id: project.id)
      forked_project.save

      @created_internal = project.internal?
      @fork_created_internal = forked_project.internal?
    end

    context 'updates forks visibility level when parent set to more restrictive' do
      before do
        opts.merge!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
        update_project(project, user, opts).inspect
      end

      it { expect(@created_internal).to be_truthy }
      it { expect(@fork_created_internal).to be_truthy }
      it { expect(project.private?).to be_truthy }
      it { expect(project.forks.first.private?).to be_truthy }
    end

    context 'does not update forks visibility level when parent set to less restrictive' do
      before do
        opts.merge!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
        update_project(project, user, opts).inspect
      end

      it { expect(@created_internal).to be_truthy }
      it { expect(@fork_created_internal).to be_truthy }
      it { expect(project.public?).to be_truthy }
      it { expect(project.forks.first.internal?).to be_truthy }
    end
  end

  describe 'repository_storage' do
    let(:admin_user) { create(:user, admin: true) }
    let(:user) { create(:user) }
    let(:project) { create(:project, repository_storage: 'a') }
    let(:opts) { { repository_storage: 'b' } }

    before do
      FileUtils.mkdir('tmp/tests/storage_a')
      FileUtils.mkdir('tmp/tests/storage_b')

      storages = { 'a' => 'tmp/tests/storage_a', 'b' => 'tmp/tests/storage_b' }
      allow(Gitlab.config.repositories).to receive(:storages).and_return(storages)
    end

    after do
      FileUtils.rm_rf('tmp/tests/storage_a')
      FileUtils.rm_rf('tmp/tests/storage_b')
    end

    it 'calls the change repository storage method if the storage changed' do
      expect(project).to receive(:change_repository_storage).with('b')

      update_project(project, admin_user, opts).inspect
    end

    it "doesn't call the change repository storage for non-admin users" do
      expect(project).not_to receive(:change_repository_storage)

      update_project(project, user, opts).inspect
    end
  end

  def update_project(project, user, opts)
    Projects::UpdateService.new(project, user, opts).execute
  end
end
