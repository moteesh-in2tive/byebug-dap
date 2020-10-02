require 'dap'
require 'byebug'
require 'byebug/core'
require 'byebug/remote'
require_relative 'dap/handles'
require_relative 'dap/command_processor'
require_relative 'dap/interface'
require_relative 'remote/server'

module Byebug
  class << self
    def start_dap(unix:)
      dap.start_unix(unix)
    end

    def run_dap(*args, **kwargs)
      Byebug.mode = :attached
      Byebug.start_dap(*args, **kwargs)
      Byebug.start
      yield
    end

    private

    def dap
      @dap ||= Byebug::Remote::Server.new(wait_connection: false) do |s|
        Context.interface = Byebug::DAP::Interface.new(s)
        Context.processor = Byebug::DAP::CommandProcessor

        Context.processor.new(Byebug.current_context, Context.interface).process_commands
      rescue EOFError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        puts "\nClient disconnected"
      rescue StandardError => e
        puts "#{e.message} #{e.class}", *e.backtrace
      end
    end
  end
end
