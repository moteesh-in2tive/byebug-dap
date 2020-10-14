module Byebug::DAP
  # Implementation of a DAP command that must be executed in-context.
  # @abstract Subclasses must implement {#execute_in_context}
  class ContextualCommand < Command
    # (see Command.resolve!)
    # @note Raises an error if the resolved class is not a subclass of {ContextualCommand}
    def self.resolve!(session, request)
      return unless cls = super
      return cls if cls < ContextualCommand

      raise "Not a contextual command: #{command}"
    end

    # Create a new instance of the receiver.
    # @param session [Session] the debug session
    # @param request [Protocol::Request] the DAP request
    # @param processor [CommandProcessor] the command processor associated with the context
    def initialize(session, request, processor = nil)
      super(session, request)
      @processor = processor
      @context = processor&.context
    end

    # {#execute_in_context Execute in-context} if `processor` is defined.
    # Otherwise, ensure debugging is {#started! started}, find the requested
    # thread context, and {#forward_to_context forward the request}.
    def execute
      return execute_in_context if @processor

      started!

      forward_to_context find_thread(args.threadId)
    end

    private

    # Forward the request to the context's thread.
    # @param ctx [gem:byebug:Byebug::Context] the context
    # @api private
    # @!visibility public
    def forward_to_context(ctx)
      ctx.processor << @request
    end
  end
end
