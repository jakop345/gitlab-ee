class LdapGroupSyncWorker
  include Sidekiq::Worker

  def perform
    logger.info 'Updating LDAP group membership'
    group_sync = Gitlab::LDAP::GroupSync.new
    group_sync.update_permissions
    logger.info 'Finished updating LDAP group membership'
  end
end
