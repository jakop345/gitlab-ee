class ApproverGroup < ActiveRecord::Base
  belongs_to :target, polymorphic: true
  belongs_to :group

  validates :group, presence: true

  def users
    group.members.map(&:user)
  end
end
