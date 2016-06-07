FactoryGirl.define do
  factory :path_lock do
    project
    user { create :user }
    sequence(:path) { |n| "app/model#{n}" }
  end
end
