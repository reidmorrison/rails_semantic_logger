class CreateSamples < ActiveRecord::Migration
  def change
    create_table :samples do |t|
      t.string :name
      t.integer :age
      t.date :joined

      t.timestamps null: false
    end
  end
end
