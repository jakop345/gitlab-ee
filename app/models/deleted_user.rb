class DeletedUser < User
  def initialize
    super
    assign_attributes(deleted_user_params)
  end

  private

  def deleted_user_params
    {
      name: '[deleted]',
      email: 'deleted@example.com',
      username: '_'
    }
  end
end
