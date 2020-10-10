module Byebug::DAP
  class Command::Scopes < Command
    # "The request returns the variable scopes for a given stackframe ID.

    register!

    def execute
      started!

      frame, thnum, frnum = resolve_frame_id(args.frameId)
      return unless frame

      scopes = []

      locals = frame_local_names(frame).sort
      unless locals.empty?
        scopes << ::DAP::Scope.new(
          name: 'Locals',
          presentationHint: 'locals',
          variablesReference: @session.save_variables(thnum, frnum, :locals, locals),
          namedVariables: locals.size,
          indexedVariables: 0,
          expensive: false)
          .validate!
      end

      globals = global_names.sort
      unless globals.empty?
        scopes << ::DAP::Scope.new(
          name: 'Globals',
          presentationHint: 'globals',
          variablesReference: @session.save_variables(thnum, frnum, :globals, globals),
          namedVariables: globals.size,
          indexedVariables: 0,
          expensive: true)
          .validate!
      end

      respond! body: ::DAP::ScopesResponseBody.new(scopes: scopes)
    end

    private

    def frame_local_names(frame)
      locals = frame.locals
      locals = locals.keys unless locals == [] # BUG in Byebug?
      locals << :self if frame._self.to_s != 'main'
      locals
    end

    def global_names
      global_variables - %i[$IGNORECASE $= $KCODE $-K $binding]
    end
  end
end
