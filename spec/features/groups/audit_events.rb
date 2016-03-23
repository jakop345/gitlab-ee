require 'spec_helper'

feature 'Groups > Audit Events', js: true, feature: true do
  let(:user) { create(:user) }
  let(:pete) { create(:user, name: 'Pete') }

  let(:project) { create(:project, namespace: user.namespace) }

  before do
    project.team << [user, :master]
    project.team << [pete, :developer]
    login_with(user)
  end

  describe 'changing a user access level' do
    it "appears in the group's audit events" do
      visit namespace_project_path(project.namespace, project)

      click_link 'Members'

      project_member = project.project_members.find_by(user_id: pete)
      page.within "#project_member_#{project_member.id}" do
        click_button 'Edit access level'
        select 'Master', from: 'project_member_access_level'
        click_button 'Save'
      end

      # This is to avoid a Capybara::Poltergeist::MouseEventFailed error
      find('a[title=Settings]').trigger('click')

      click_link 'Audit Events'

      page.within('table#audits') do
        expect(page).to have_content 'Change access level from developer to master'
        expect(page).to have_content(project.owner.name)
        expect(page).to have_content('Pete')
      end
    end
  end
end
