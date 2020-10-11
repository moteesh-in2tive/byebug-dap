module Byebug::DAP
  class ContextualCommand < Command
    def self.resolve!(session, request)
      return unless cls = super
      return cls if cls < ContextualCommand

      raise "Not a contextual command: #{command}"
    end

    def initialize(session, request, processor = nil)
      super(session, request)
      @processor = processor
      @context = processor&.context
    end

    def execute
      return execute_in_context if @processor

      started!

      forward_to_context find_thread(args.threadId)
    end

    private

    def forward_to_context(ctx)
      ctx.processor << @request
    end
  end
end
