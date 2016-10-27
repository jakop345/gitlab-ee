require 'rails_helper'

describe RepositoryUpdateRemoteMirrorWorker do
  let(:mirror) { create(:remote_mirror) }

  describe '#perform' do
    it 'does nothing if project is missing' do
      mirror.update!(project_id: nil)

      expect(described_class.new.perform(mirror.id)).to be_nil
    end
  end
end
