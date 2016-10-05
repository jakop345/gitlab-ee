FactoryGirl.define do
  factory :board do
    sequence(:name) { |n| "board#{n}" }
    project factory: :empty_project
  end
end
