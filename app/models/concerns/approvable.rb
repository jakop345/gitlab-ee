module Approvable
  extend ActiveSupport::Concern

  included do
    def requires_approve?
      approvals_required.nonzero?
    end

    def approved?
      approvals_left < 1
    end

    # Number of approvals remaining (excluding existing approvals) before the MR is
    # considered approved. If there are fewer potential approvers than approvals left,
    # choose the lower so the MR doesn't get 'stuck' in a state where it can't be approved.
    #
    def approvals_left
      @approvals_left ||= [
        [approvals_required - approvals.count, number_of_potential_approvers].min,
        0
      ].max
    end

    # Expire internal memoized state, introduced to reduce database queries, that should
    # be called after we update/create the merge request approval configuration or when
    # some user approve the merge request.
    def approvable_expire_state
      @approvals_left = nil
      @approver_ids_including_groups = nil
      @approvers_overwritten = nil
    end

    def approvals_required
      approvals_before_merge || target_project.approvals_before_merge
    end

    # An MR can potentially be approved by:
    # - anyone in the approvers list
    # - any other project member with developer access or higher (if there are no approvers
    #   left)
    #
    # It cannot be approved by:
    # - a user who has already approved the MR
    # - the MR author
    #
    def number_of_potential_approvers
      has_access = ['access_level > ?', Member::REPORTER]
      wheres = [
        "id IN (#{project.members.where(has_access).select(:user_id).to_sql})",
        "id IN (#{all_approver_ids_including_groups_relation.to_sql})"
      ]

      if project.group
        wheres << "id IN (#{project.group.members.where(has_access).select(:user_id).to_sql})"
      end

      User.
        active.
        where("(#{wheres.join(' OR ')}) AND id NOT IN (#{approvals.select(:user_id).to_sql})").
        where.not(id: author.id).
        count
    end

    # Users in the list of approvers who have not already approved this MR.
    # Memoized because it's used a lot of times during a request.
    #
    def approvers_left
      @approvers_left ||=
        User.where("id IN (#{all_approver_ids_including_groups_relation.to_sql})").
          where.not(id: approvals.select(:user_id)).
          to_a
    end

    def approvers_left_names
      approvers_left.map(&:name)
    end

    # The list of approvers from either this MR (if they've been set on the MR) or the
    # target project. Excludes the author by default.
    #
    # Before a merge request has been created, author will be nil, so pass the current user
    # on the MR create page.
    #
    def overall_approvers
      approvers_relation = approvers_overwritten? ? approvers : target_project.approvers

      approvers_relation = approvers_relation.where.not(user_id: author.id) if author

      approvers_relation
    end

    def overall_approver_groups
      approvers_overwritten? ? approver_groups : target_project.approver_groups
    end

    def all_approver_ids_including_groups
      @approver_ids_including_groups ||= User.where("id IN (#{all_approver_ids_including_groups_relation.to_sql})").pluck(:id)
    end

    def all_approver_ids_including_groups_relation
      overall_approver_ids = overall_approvers.select(:user_id)

      overall_approver_ids_from_groups = overall_approver_groups.joins(group: :group_members)
      overall_approver_ids_from_groups = overall_approver_ids_from_groups.where("members.user_id != ?", author.id) if author
      overall_approver_ids_from_groups = overall_approver_ids_from_groups.select("DISTINCT members.user_id")

      Gitlab::SQL::Union.new([
        overall_approver_ids,
        overall_approver_ids_from_groups
      ])
    end
    private :all_approver_ids_including_groups_relation

    def approvers_overwritten?
      return @approvers_overwritten if defined?(@approvers_overwritten) && !@approvers_overwritten.nil?

      @approvers_overwritten = approvers.any? || approver_groups.any?
    end

    def can_approve?(user)
      return false unless user
      return true if approvers_left.include?(user)
      return false if user == author
      return false unless user.can?(:update_merge_request, self)

      approval?(user) && any_approver_allowed?
    end

    def approval?(user)
      if approvals.loaded?
        approvals.none? { |approval| approval.user_id == user.id }
      else
        !approvals.where(user_id: user.id).exists?
      end
    end

    # Once there are fewer approvers left in the list than approvals required, allow other
    # project members to approve the MR.
    #
    def any_approver_allowed?
      approvals_left > approvers_left.size
    end

    def approved_by_users
      approvals.map(&:user)
    end

    def approver_ids=(value)
      value.split(",").map(&:strip).each do |user_id|
        next if author && user_id == author.id

        approvers.find_or_initialize_by(user_id: user_id, target_id: id)
      end
    end

    def approver_group_ids=(value)
      value.split(",").map(&:strip).each do |group_id|
        approver_groups.find_or_initialize_by(group_id: group_id, target_id: id)
      end
    end
  end
end
