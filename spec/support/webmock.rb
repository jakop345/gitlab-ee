require 'webmock'
require 'webmock/rspec'

WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: ['elasticsearch', ENV['ELASTIC_HOST'] || 'registry.gitlab.com-gitlab-org-test-elastic-image']
)
