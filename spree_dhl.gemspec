# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'spree_dhl/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_dhl'
  s.version     = SpreeDhl::VERSION
  s.summary     = "Spree Commerce Dhl Extension"
  s.required_ruby_version = '>= 3.2'

  s.author    = 'Matthew Kennedy'
  s.email     = 'm.kennedy@me.com'
  s.homepage  = 'https://github.com/MatthewKennedy/spree_dhl'
  s.license   = 'AGPL-3.0-or-later'

  s.files        = Dir["{app,config,db,lib,vendor}/**/*", "LICENSE.md", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree', '>= 5.3.3'
  s.add_dependency 'spree_admin', '>= 5.3.3'
  s.add_dependency 'spree_storefront', '>= 5.3.3'
  s.add_dependency 'spree_extension'
end
