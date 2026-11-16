# frozen_string_literal: true

class AddDownloadCountToReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :download_count, :bigint, default: 0, null: false
  end
end
