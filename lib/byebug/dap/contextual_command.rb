module Byebug::DAP
  class ContextualCommand < Command
    def execute
      return execute_in_context if @processor

      started!

      forward_to_context find_thread(args.threadId)

      respond!
    end

    def self.resolve!(command)
      cls = super
      raise "Not a contextual command: #{command}" unless cls < ContextualCommand
      cls
    end

    private

    def forward_to_context(ctx)
      ctx.__send__(:processor) << @request
    end
  end
end
