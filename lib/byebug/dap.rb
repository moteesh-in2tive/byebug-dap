require 'dap'
require 'byebug'
require 'byebug/core'
require 'byebug/remote'

require_relative 'dap/channel'
require_relative 'dap/handles'
require_relative 'dap/invalid_request_argument_error'
require_relative 'dap/safe_helpers'

require_relative 'dap/server'
require_relative 'dap/command_processor'
require_relative 'dap/controller'
require_relative 'dap/interface'

module Byebug
  module DAP
    module Debug
      class << self
        @protocol = false
        @evaluate = false

        attr_accessor :protocol, :evaluate
      end
    end
  end

  class << self
    def start_dap(host, port = 0, &block)
      DAP::Server.new(&block).start(host, port)
    end
  end
end
