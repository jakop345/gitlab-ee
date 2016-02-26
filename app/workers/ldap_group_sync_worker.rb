class LdapGroupSyncWorker
  include Sidekiq::Worker

  def perform
    logger.info 'Started LDAP group sync'
    group_sync = Gitlab::LDAP::GroupSync.new
    group_sync.update_permissions
    logger.info 'Finished LDAP group sync'
  end
end
