Gem::Specification.new do |s|
    s.name        = 'byebug-dap'
    s.version     = '0.1.1'
    s.summary     = 'Debug Adapter Protocol for Byebug'
    s.description = 'Implements a Debug Adapter Protocol interface for Byebug'
    s.authors     = ['Ethan Reesor']
    s.email       = 'ethan.reesor@gmail.com'
    s.files       = Dir.glob('{bin,lib}/**/*.rb') + %w(LICENSE AUTHORS README.md CHANGELOG.md)
    s.executables = ['byebug-dap']
    s.homepage    = 'https://gitlab.com/firelizzard/byebug-dap'
    s.license     = 'Apache-2.0'

    s.add_runtime_dependency 'byebug', '~> 11.1'
    s.add_runtime_dependency 'ruby-dap', '~> 0.1.0'
  end
