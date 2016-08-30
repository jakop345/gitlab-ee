# Custom rules which will be checked on each file content
# present on commit.
#
# This rules are written especially to prevent secrets like
# private keys to be pushed accidentaly into a repository.
#
# Any file content into the commit which matches the ruby regular expression
# will prevent the push to happen.

class CustomRule < ActiveRecord::Base
  belongs_to :push_rule
  validates :push_rule_id, :title, :regex, presence: true

  scope :enabled_rules, -> { where(enabled: true) }
end
