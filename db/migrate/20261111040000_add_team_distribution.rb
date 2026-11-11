class AddTeamDistribution < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :distribution_status, :string, default: 'testing', null: false
    add_column :releases, :test_notes, :text
    add_column :releases, :issue_url, :string
    add_column :releases, :file_sha256, :string
    add_column :releases, :share_version, :integer, default: 0, null: false
    add_column :releases, :share_expires_at, :datetime
    add_index :releases, [:channel_id, :file_sha256]
    add_reference :channels, :recommended_release, foreign_key: { to_table: :releases, on_delete: :nullify }
    add_column :schemes, :share_version, :integer, default: 0, null: false
    add_column :schemes, :share_expires_at, :datetime
  end
end
