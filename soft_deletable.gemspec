# frozen_string_literal: true

require_relative 'lib/soft_deletable/version'

Gem::Specification.new do |spec|
  spec.name        = 'soft_deletable'
  spec.version     = SoftDeletable::VERSION
  spec.authors     = ['Minty Fresh']
  spec.email       = ['7896757+mintyfresh@users.noreply.github.com']
  spec.homepage    = 'https://github.com/mintyfresh/soft_deletable'
  spec.summary     = 'Soft-deletable models for Rails'
  spec.description = 'Manages soft-deletion of records, with cascading soft-deletion and restoration of associations.'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.2'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'rails', '>= 8'
end
