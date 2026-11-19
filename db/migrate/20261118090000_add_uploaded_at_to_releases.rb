class AddUploadedAtToReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :uploaded_at, :datetime
  end
end
