require 'rails_helper'

describe UpdateAllRemoteMirrorsWorker do
  let(:worker) { described_class.new }

  describe '#perform' do
    context 'stuck mirrors' do
      let!(:mirror) { create(:remote_mirror, update_status: :started, last_update_at: 1.week.ago) }

      it 'are transitioned to failure state' do
        worker.perform

        expect(mirror.reload.update_status).to eq 'failed'
      end

      it 'handles enabled mirrors with missing project' do
        mirror.update!(project: nil, enabled: true)

        worker.perform

        expect(mirror.reload.update_status).to eq 'failed'
      end
    end
  end
end
