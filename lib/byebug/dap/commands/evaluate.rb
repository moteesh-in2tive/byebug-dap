module Byebug::DAP
  class Command::Evaluate < Command
    # "Evaluates the given expression in the context of the top most stack frame.
    # "The expression has access to any variables and arguments that are in scope.

    include ValueHelpers

    register!

    def execute
      started!

      respond! body: evaluate
    end

    private

    def evaluate
      return prepare_value_response(0, 0, :evaluate) { TOPLEVEL_BINDING.eval(args.expression) } unless args.frameId

      frame, thnum, frnum = resolve_frame_id(args.frameId)
      return unless frame

      prepare_value_response(thnum, frnum, :evaluate) { frame._binding.eval(args.expression) }
    end
  end
end
