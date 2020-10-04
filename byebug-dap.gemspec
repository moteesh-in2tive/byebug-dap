Gem::Specification.new do |s|
    s.name        = 'byebug-dap'
    s.version     = '0.0.0'
    s.date        = '2020-09-30'
    s.summary     = 'Debug Adapter Protocol for Byebug'
    s.description = 'Implements a Debug Adapter Protocol interface for Byebug'
    s.authors     = ['Ethan Reesor']
    s.email       = 'ethan.reesor@gmail.com'
    s.files       = ['lib/byebug/dap.rb']
    s.executables = ['byebug-dap']
    s.homepage    = 'https://gitlab.com/firelizzard/byebug-dap'
    s.license     = 'GPLv3'

    s.add_runtime_dependency 'byebug'
    s.add_runtime_dependency 'ruby-dap'
    s.add_runtime_dependency 'concurrent-ruby-edge'
  end
