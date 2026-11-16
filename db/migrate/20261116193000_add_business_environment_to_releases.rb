class AddBusinessEnvironmentToReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :business_environment, :string
    add_check_constraint :releases,
                         "business_environment IS NULL OR business_environment IN ('testing', 'production')",
                         name: 'releases_business_environment_allowed'
  end
end
