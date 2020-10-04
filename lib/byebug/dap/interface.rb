module Byebug
  module DAP
    class Interface
      include SafeHelpers

      @@debug = false

      def self.enable_debug
        @@debug = true
      end

      attr_reader :socket

      def initialize(socket)
        @socket = socket
      end

      def <<(message)
        STDERR.puts "> #{message.to_wire}" if @@debug
        message.validate!
        socket.write ::DAP::Encoding.encode(message)
      end

      def event!(event, **values)
        body = ::DAP.const_get("#{event[0].upcase}#{event[1..]}EventBody").new(values) unless values.empty?
        self << ::DAP::Event.new(event: event, body: body)
      end

      def receive
        m = ::DAP::Encoding.decode(socket)
        STDERR.puts "< #{m.to_wire}" if @@debug
        m
      end

      def invalidate_handles!
        frame_ids.clear!
        variable_refs.clear!
      end

      def threads
        Byebug.contexts
          .map { |ctx| ::DAP::Thread.new(
            id: ctx.thnum,
            name: ctx.thread.name || "Thread ##{ctx.thnum}" )
            .validate!}
      end

      def find_thread(id)
        raise InvalidRequestArgumentError.new(:missing_argument, scope: 'thread ID') unless id

        ctx = Byebug.contexts.find { |c| c.thnum == id }
        raise InvalidRequestArgumentError.new(:missing_thread, value: id) unless ctx

        ctx
      end

      def resolve_frame_id(id)
        entry = frame_ids[id]
        raise InvalidRequestArgumentError.new(:missing_entry, value: id, scope: 'frame ID') unless entry

        thnum, frnum = entry
        ctx = Byebug.contexts.find { |c| c.thnum == thnum }
        raise InvalidRequestArgumentError.new(:missing_thread, value: thnum) unless ctx
        raise InvalidRequestArgumentError.new(:missing_frame, value: frnum) unless frnum < ctx.stack_size

        return ::Byebug::Frame.new(ctx, frnum), thnum, frnum
      end

      def frames(thnum, at:, count:)
        ctx = find_thread(thnum)

        first = at || 0
        if !count
          last = ctx.stack_size
        else
          last = first + count
          if last > ctx.stack_size
            last = ctx.stack_size
          end
        end

        frames = (first...last).map do |i|
          frame = ::Byebug::Frame.new(ctx, i)
          ::DAP::StackFrame.new(
            id: frame_ids << [ctx.thnum, i],
            name: frame.deco_call,
            source: ::DAP::Source.new(
              name: File.basename(frame.file),
              path: File.expand_path(frame.file)),
            line: frame.line,
            column: 0) # TODO real column
            .validate!
        end

        return frames, ctx.stack_size
      end

      def resolve_variable_ref(ref)
        entry = variable_refs[ref]
        raise InvalidRequestArgumentError.new(:missing_entry, value: ref, scope: 'variables reference') unless entry

        thnum, frnum, kind, *entry = entry

        case kind
        when :locals
          ctx = find_thread(thnum)
          raise InvalidRequestArgumentError.new(:missing_frame, value: frnum) unless frnum < ctx.stack_size

          frame = ::Byebug::Frame.new(ctx, frnum)

          return kind, entry[0], ->(key) {
            return frame._self if key == :self
            values ||= frame.locals
            values[key]
          }
        when :globals
          return kind, entry[0], ->(key) { frame._binding.eval(key.to_s) }
        when :variable, :evalate
          value, named, indexed = entry
          return kind, named, ->(key) { value.instance_eval { binding }.eval(key.to_s) }
        else
          raise InvalidRequestArgumentError.new(:invalid_entry, value: kind, scope: 'variable scope')
        end
      end

      def scopes(frameId)
        raise InvalidRequestArgumentError.new(:missing_argument, scope: 'frame ID') unless frameId

        frame, thnum, frnum = resolve_frame_id(frameId)
        return unless frame

        scopes = []

        locals = frame_local_names(frame).sort
        unless locals.empty?
          scopes << ::DAP::Scope.new(
            name: 'Locals',
            presentationHint: 'locals',
            variablesReference: variable_refs << [thnum, frnum, :locals, locals],
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
            variablesReference: variable_refs << [0, 0, :globals, globals],
            namedVariables: globals.size,
            indexedVariables: 0,
            expensive: true)
            .validate!
        end

        scopes
      end

      def variables(varRef, at:, count:, filter: nil)
        raise InvalidRequestArgumentError.new(:missing_argument, scope: 'variables reference') unless varRef

        kind, scope, get = resolve_variable_ref(varRef)
        return unless kind

        # TODO support structured variables
        unless filter.nil? || filter == 'named'
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
          raw, value, type, named, indexed = prepare_value_from(get, :call, var) { ["*Error in evaluation*", nil] }

          args = {name: var, value: value, type: type}
          if named.empty? && indexed.empty?
            args[:variablesReference] = 0
          else
            args[:variablesReference] = variable_refs << [0, 0, :variable, raw, named, indexed]
            args[:namedVariables] = named.size
            args[:indexedVariables] = indexed.size
          end

          ::DAP::Variable.new(args).validate!
        end
      end

      def evaluate(frameId, expression)
        frame, thnum, frnum = resolve_frame_id(frameId)
        return unless frame

        # TODO support structured values
        raw, value, type, named, indexed = prepare_value_from(frame._binding, :eval, expression) { ["*Error in evaluation*", nil] }

        args = {result: value, type: type}
        if named.empty? && indexed.empty?
          args[:variablesReference] = 0
        else
          args[:variablesReference] = variable_refs << [0, 0, :evaluate, raw, named, indexed]
          args[:namedVariables] = named.size
          args[:indexedVariables] = indexed.size
        end

        ::DAP::EvaluateResponseBody.new(args).validate!
      end

      private

      def frame_ids
        @frame_ids ||= Handles.new
      end

      def variable_refs
        @variable_refs ||= Handles.new
      end

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
end
