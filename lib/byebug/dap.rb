require 'dap'
require 'byebug'
require 'byebug/core'
require 'byebug/remote'
require 'concurrent-edge'
require_relative 'dap/handles'
require_relative 'dap/safe_helpers'
require_relative 'dap/invalid_request_argument_error'
require_relative 'dap/command_processor'
require_relative 'dap/controller'
require_relative 'dap/interface'
require_relative 'remote/server'

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
    def start_dap(host, port = 0)
      return dap.start_stdio if host == :stdio
      return dap.start_unix(port) if host == :unix
      return dap.start(host, port)
    end

    def run_dap(*args, **kwargs)
      Byebug.start_dap(*args, **kwargs)
      yield
    end

    private

    def dap
      @dap ||= Byebug::Remote::Server.new(wait_connection: false) do |s|
        Context.interface = Byebug::DAP::Interface.new(s)
        Context.processor = Byebug::DAP::CommandProcessor

        Byebug::DAP::Controller.new(Context.interface).process_commands
      end
    end
  end
end
