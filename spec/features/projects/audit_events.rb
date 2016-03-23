require 'spec_helper'

feature 'Projects > Audit Events', feature: true do
  let(:user) { create(:user) }
  let(:project) { create(:project, namespace: user.namespace) }

  before do
    project.team << [user, :master]
    login_with(user)
  end

  describe 'initial login after setup' do
    it "appears in the project's audit events" do
      visit new_namespace_project_deploy_key_path(project.namespace, project)

      fill_in 'deploy_key_title', with: 'laptop'
      fill_in 'deploy_key_key', with: 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAzrEJUIR6Y03TCE9rIJ+GqTBvgb8t1jI9h5UBzCLuK4VawOmkLornPqLDrGbm6tcwM/wBrrLvVOqi2HwmkKEIecVO0a64A4rIYScVsXIniHRS6w5twyn1MD3sIbN+socBDcaldECQa2u1dI3tnNVcs8wi77fiRe7RSxePsJceGoheRQgC8AZ510UdIlO+9rjIHUdVN7LLyz512auAfYsgx1OfablkQ/XJcdEwDNgi9imI6nAXhmoKUm1IPLT2yKajTIC64AjLOnE0YyCh6+7RFMpiMyu1qiOCpdjYwTgBRiciNRZCH8xIedyCoAmiUgkUT40XYHwLuwiPJICpkAzp7Q== user@laptop'

      click_button 'Create'

      visit namespace_project_audit_events_path(project.namespace, project)

      expect(page).to have_content('Add deploy key')

      visit namespace_project_deploy_keys_path(project.namespace, project)
      click_link 'Remove'

      visit namespace_project_audit_events_path(project.namespace, project)

      expect(page).to have_content('Remove deploy key')
    end
  end
end
