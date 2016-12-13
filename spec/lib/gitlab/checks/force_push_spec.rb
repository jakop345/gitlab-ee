require 'spec_helper'

describe Gitlab::Checks::ChangeAccess, lib: true do
  let(:project) { create(:project) }

  context "exit code checking" do
    it "does not raise a runtime error if the `popen` call to git returns a zero exit code" do
      allow(Gitlab::Popen).to receive(:popen).and_return(['normal output', 0])

      expect { Gitlab::Checks::ForcePush.force_push?(project, 'oldrev', 'newrev') }.not_to raise_error
    end

    it "raises a runtime error if the `popen` call to git returns a non-zero exit code" do
      allow(Gitlab::Popen).to receive(:popen).and_return(['error', 1])

      expect { Gitlab::Checks::ForcePush.force_push?(project, 'oldrev', 'newrev') }.to raise_error(RuntimeError)
    end
  end
end
