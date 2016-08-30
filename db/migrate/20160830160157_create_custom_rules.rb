class CreateCustomRules < ActiveRecord::Migration
  DOWNTIME = false

  def change
    create_table :custom_rules do |t|
      t.belongs_to :push_rule, index: true
      t.string :title
      t.string :regex
      t.boolean :enabled
    end
  end
end
