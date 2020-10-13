require 'dap'
require 'byebug'
require 'byebug/core'
require 'byebug/remote'

require_relative 'gem'

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
    # Creates and starts the server. See {DAP::Server#initialize} and
    # {DAP::Server#start}.
    # @param host the host passed to {DAP::Server#start}
    # @param port the port passed to {DAP::Server#start}
    # @return [DAP::Server]
    def start_dap(host, port = 0)
      DAP::Server.new.start(host, port)
    end
  end

  class Context
    public :processor
  end

  class Frame
    attr_reader :context
  end
end

module Byebug::DAP
  # An alias for `ruby-dap`'s {DAP} module.
  Protocol = ::DAP

  class << self
    # (see Session.stop!)
    def stop!
      Session.stop!
    end

    # (see Session.child_spawned)
    def child_spawned(*args)
      Session.child_spawned(*args)
    end
  end
end

# Debug logging
module Byebug::DAP::Debug
  class << self
    @protocol = false
    @evaluate = false

    # Log all sent and received protocol messages.
    # @return [Boolean]
    attr_accessor :protocol

    # Log evaluation failures.
    # @return [Boolean]
    attr_accessor :evaluate
  end
end
