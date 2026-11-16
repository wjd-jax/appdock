# frozen_string_literal: true

class BackfillBusinessEnvironmentOnReleases < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE releases SET business_environment = 'testing' WHERE business_environment IS NULL"
    change_column_default :releases, :business_environment, from: nil, to: 'testing'
    change_column_null :releases, :business_environment, false
  end

  def down
    change_column_null :releases, :business_environment, true
    change_column_default :releases, :business_environment, from: 'testing', to: nil
  end
end
