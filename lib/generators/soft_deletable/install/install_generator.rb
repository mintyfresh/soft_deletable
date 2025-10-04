# frozen_string_literal: true

module SoftDeletable
  class InstallGenerator < Rails::Generators::NamedBase
    source_root File.expand_path('templates', __dir__)

    def copy_soft_deletable_rb
      copy_file 'soft_deletable.rb', 'config/initializers/soft_deletable.rb'
    end
  end
end
