require 'rails_helper'

describe 'Issue Boards shortcut', feature: true, js: true do
  include WaitForVueResource

  let(:project) { create(:empty_project) }
  let!(:board)  { create(:board, project: project) }

  before do
    login_as :admin

    visit namespace_project_path(project.namespace, project)
  end

  it 'takes user to issue board index' do
    find('body').native.send_keys('gl')
    expect(page).to have_selector('.boards-list')

    wait_for_vue_resource
  end
end
