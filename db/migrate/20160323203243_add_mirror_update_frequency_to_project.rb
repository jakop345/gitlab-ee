class AddMirrorUpdateFrequencyToProject < ActiveRecord::Migration
  def change
    add_column :projects, :mirror_update_frequency, :integer, default: 1.day
  end
end
