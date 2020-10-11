require 'dap'
require 'byebug'
require 'byebug/core'
require 'byebug/remote'

Byebug::DAP = Module.new

# load helpers
Dir[File.join(__dir__, 'dap', 'helpers', '*.rb')].each { |file| require file }

# load command base classes
require_relative 'dap/command'
require_relative 'dap/contextual_command'

# load commands
Dir[File.join(__dir__, 'dap', 'commands', '*.rb')].each { |file| require file }

# load everything else
require_relative 'dap/command_processor'
require_relative 'dap/session'
require_relative 'dap/server'

module Byebug
  class << self
    def start_dap(host, port = 0, &block)
      DAP::Server.new(&block).start(host, port)
    end
  end

  class Context
    public :processor
  end
end

module Byebug::DAP
  class << self
    def child_spawned(*args)
      Session.child_spawned(*args)
    end

    def stop!
      interface = Byebug::Context.interface
      return false unless interface.is_a?(Session)

      interface.stop!
      true
    end
  end
end

module Byebug::DAP::Debug
  class << self
    @protocol = false
    @evaluate = false

    attr_accessor :protocol, :evaluate
  end
end
