module Byebug
  module DAP
    class Interface
      attr_reader :socket

      def initialize(socket)
        @socket = socket
      end

      def puts(message)
        socket.write ::DAP::Encoding.encode(message)
      end

      def gets
        ::DAP::Encoding.decode(socket)
      end

      def frame_ids
        @frame_ids ||= Handles.new
      end

      def variable_refs
        @variable_refs ||= Handles.new
      end

      def threads
        Byebug
          .contexts
          # .sort_by(&:thnum)
          .map { |ctx| ::DAP::Thread.new(
            id: ctx.thnum,
            name: ctx.thread.name || "Thread ##{ctx.thnum}" )}
      end

      def resolve_frame_id(id)
        entry = frame_ids[id]
        return yield(:missing_entry, id) unless entry

        thnum, frnum = entry
        ctx = Byebug.contexts.find { |c| c.thnum == thnum }
        return yield(:missing_thread, thnum) unless ctx
        return yield(:missing_frame, frnum) unless frnum < ctx.stack_size

        ::Byebug::Frame.new(ctx, frnum)
      end

      def frames(thnum, at:, count:)
        ctx = Byebug.contexts.find { |c| c.thnum == thnum }
        return yield(:missing_thread, thnum) unless ctx

        first = at || 0
        if !count
          last = ctx.stack_size
        else
          last = first + count
          if last > ctx.stack_size
            last = ctx.stack_size
          end
        end

        (first...last).map do |i|
          frame = ::Byebug::Frame.new(ctx, i)
          ::DAP::StackFrame.new(
            id: interface.stack_frames << [ctx.thnum, i],
            name: frame.deco_call,
            source: ::DAP::Source.new(
              name: File.basename(frame.file),
              path: File.expand_path(frame.file)),
            line: frame.line)
        end
      end

      def resolve_variable_ref(ref)
        entry = variable_refs[ref]
        return yield(:missing_entry, ref) unless entry

        thnum, frnum, kind, *entry = entry
        ctx = Byebug.contexts.find { |c| c.thnum == thnum }
        return yield(:missing_thread, thnum) unless ctx
        return yield(:missing_frame, frnum) unless frnum < ctx.stack_size

        frame = ::Byebug::Frame.new(ctx, frnum)

        case kind
        when :arguments, :locals
          kind, entry[0], ->(key) do
            values ||= frame.locals
            values[key]
          end
        when :globals
          kind, entry[0], ->(key) { frame._binding.eval(n.to_s) }
        else
          return yield(:invalid_entry, "Unknown variable scope #{kind}")
        end
      end

      def scopes(frameId, &block)
        frame = resolve_frame_id(frameId, &block)
        return unless frame

        scopes = []

        args = frame_arg_names(frame).sort
        unless args.empty?
          scopes << ::DAP::Scope.new(
            name: 'Arguments',
            presentationHint: 'arguments',
            variablesReference: interface.variables << [thnum, frnum, :arguments, args],
            namedVariables: args.size,
            indexedVariables: 0,
            expensive: false)
        end

        locals = frame_local_names(frame, args: args).sort
        unless locals.empty?
          scopes << ::DAP::Scope.new(
            name: 'Locals',
            presentationHint: 'locals',
            variablesReference: interface.variables << [thnum, frnum, :locals, locals],
            namedVariables: locals.size,
            indexedVariables: 0,
            expensive: false)
        end

        globals = global_names.sort
        unless globals.empty?
          scopes << ::DAP::Scope.new(
            name: 'Globals',
            presentationHint: 'globals',
            variablesReference: interface.variables << [thnum, frnum, :globals, globals],
            namedVariables: globals.size,
            indexedVariables: 0,
            expensive: true)
        end

        scopes
      end

      def variables(varRef, at:, count:, kind: nil, &block)
        kind, scope, get = resolve_variable_ref(varRef, &block)
        return unless kind

        # TODO support structured variables
        unless kind.nil? || kind == 'named'
          return []
        end

        first = at || 0
        if !count
          last = scope.size
        else
          last = first + count
          if last > scope.size
            last = scope.size
          end
        end

        scope[first...last].map do |var|
          value = get.call(var)
          ::DAP::Variable.new(
            name: var,
            value: value,
            type: value.class.name)
        end
      end

      def evaluate(frameId, expression, &block)
        frame = resolve_frame_id(frameId, &block)
        return unless frame

        # TODO support structured values
        value = frame._binding.eval(expression)
        ::DAP::EvaluateResponseBody.new(
          result: value,
          type: value.class.name)
      end

      private

      def frame_arg_names(frame)
        frame.args.filter { |a| a != [:rest] }.map { |kind, name| name }
      end

      def frame_local_names(frame, args: nil)
        args ||= frame_arg_names(frame)
        frame.locals.keys - args + (frame._self.to_s == 'main' ? [] : [:self])
      end

      def global_names
        global_variables - %i[$IGNORECASE $= $KCODE $-K $binding]
      end
    end
  end
end
