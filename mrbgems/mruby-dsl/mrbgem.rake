MRuby::Gem::Specification.new('mruby-dsl') do |spec|
  spec.license = 'MIT'
  spec.author = 'MJ'
  spec.summary = 'A base class for DSLs: registration, declarations, failures pinned to statements'
  spec.add_dependency 'mruby-json', path: File.expand_path('../mruby-json', __dir__)
  # One Ruby source is both compiled into the VM and shipped for schema/source tools.
  spec.rbfiles << File.expand_path('../../python/johnnybt_dsl/words/float64.rb', __dir__)
end
