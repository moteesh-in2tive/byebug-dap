require File.join(__dir__, 'lib', 'byebug', 'gem.rb')

Gem::Specification.new do |s|
    s.name        = Byebug::DAP::NAME
    s.version     = Byebug::DAP::VERSION
    s.summary     = Byebug::DAP::SUMMARY
    s.description = Byebug::DAP::DESCRIPTION
    s.authors     = Byebug::DAP::AUTHORS
    s.homepage    = Byebug::DAP::WEBSITE
    s.license     = Byebug::DAP::LICENSE
    s.files       = Dir.glob('{bin,lib}/**/*.rb') + %w(LICENSE AUTHORS README.md CHANGELOG.md)
    s.executables = ['byebug-dap']

    s.add_runtime_dependency 'byebug', '~> 11.1'
    s.add_runtime_dependency 'ruby-dap', '~> 0.1.2'
  end
