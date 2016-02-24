class ChangeAppearance < ActiveRecord::Migration
  def change
    change_table :appearances do |t|
      t.remove :dark_logo

      t.rename :light_logo, :header_logo
    end 
  end
end
