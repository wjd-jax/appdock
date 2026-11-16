require 'set'

class AddDistributionSlugToApps < ActiveRecord::Migration[8.1]
  RESERVED = %w[
    a access admin api apps archives assets backup catalog channels d dashboard
    debug-files developers devices distribution download graphql health login
    notifications p public releases schemes settings udid upload users workspace
  ].freeze

  def up
    add_column :apps, :distribution_slug, :string

    used = RESERVED.to_set
    select_values('SELECT lower(slug) FROM channels').each { |slug| used.add(slug) }
    select_rows('SELECT id, name FROM apps ORDER BY id').each do |id, name|
      base = name.to_s.parameterize[0, 64].sub(/-+\z/, '')
      base = 'app' if base.blank?
      candidate = base
      suffix = 0
      while used.include?(candidate)
        suffix += 1
        candidate = "#{base}-#{id}#{suffix > 1 ? "-#{suffix}" : ''}"
      end
      execute "UPDATE apps SET distribution_slug = #{connection.quote(candidate)} WHERE id = #{id.to_i}"
      used.add(candidate)
    end

    change_column_null :apps, :distribution_slug, false
    add_index :apps, :distribution_slug, unique: true
  end

  def down
    remove_index :apps, :distribution_slug
    remove_column :apps, :distribution_slug
  end
end
