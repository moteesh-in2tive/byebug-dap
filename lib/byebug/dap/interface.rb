module Byebug
  module DAP
    class Interface
      include SafeHelpers

      attr_reader :socket

      def initialize(socket)
        @socket = socket
      end

      def <<(message)
        STDERR.puts "> #{message.to_wire}" if Debug.protocol
        message.validate!
        socket.write ::DAP::Encoding.encode(message)
      end

      def event!(event, **values)
        body = ::DAP.const_get("#{event[0].upcase}#{event[1..]}EventBody").new(values) unless values.empty?
        self << ::DAP::Event.new(event: event, body: body)
      end

      def receive
        m = ::DAP::Encoding.decode(socket)
        STDERR.puts "< #{m.to_wire}" if Debug.protocol
        m
      end

      def invalidate_handles!
        frame_ids.clear!
        variable_refs.clear!
      end

      def threads
        Byebug.contexts
          .filter { |ctx| !ctx.thread.is_a?(DebugThread) }
          .map { |ctx| ::DAP::Thread.new(
            id: ctx.thnum,
            name: ctx.thread.name || "Thread ##{ctx.thnum}")
            .validate! }
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

      def resolve_variable_reference(varRef)
        raise InvalidRequestArgumentError.new(:missing_argument, scope: 'variables reference') unless varRef

        entry = variable_refs[varRef]
        raise InvalidRequestArgumentError.new(:missing_entry, value: ref, scope: 'variables reference') unless entry

        entry
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
            variablesReference: variable_refs << [thnum, frnum, :globals, globals],
            namedVariables: globals.size,
            indexedVariables: 0,
            expensive: true)
            .validate!
        end

        scopes
      end

      def variables(varRef, at:, count:, filter: nil)
        thnum, frnum, kind, *entry = resolve_variable_reference(varRef)

        case kind
        when :locals, :globals
          ctx = find_thread(thnum)
          raise InvalidRequestArgumentError.new(:missing_frame, value: frnum) unless frnum < ctx.stack_size

          frame = ::Byebug::Frame.new(ctx, frnum)
        end

        case kind
        when :locals
          named, indexed = entry[0], []
          get = ->(key) {
            return frame._self if key == :self
            values ||= frame.locals
            values[key]
          }

        when :globals
          named, indexed = entry[0], []
          get = ->(key) { frame._binding.eval(key.to_s) }

        when :variable, :evalate
          value, named, indexed = entry
          get = ->(key) { value.instance_eval { binding }.eval(key.to_s) }
          index = ->(key) { value[key] }

        else
          raise InvalidRequestArgumentError.new(:invalid_entry, value: kind, scope: 'variable scope')
        end

        case filter
        when 'named'
          indexed = []
        when 'indexed'
          named = []
        end

        vars = named.map { |k| [k, get] } + indexed.map { |k| [k, index] }

        first = at || 0
        last = count ? first + count : vars.size
        last = vars.size unless last < vars.size

        vars[first...last].map { |var, get| prepare_value_response(thnum, frnum, :variable, get, :call, var, name: var) }
      end

      def evaluate(frameId, expression)
        frame, thnum, frnum = resolve_frame_id(frameId)
        return unless frame

        prepare_value_response(thnum, frnum, :evaluate, frame._binding, :eval, expression)
      end

      private

      def prepare_value_response(thnum, frnum, kind, target, method, *margs, name: nil)
        raw, value, type, named, indexed = prepare_value_from(target, method, *margs) { [nil, "*Error in evaluation*", nil, [], []] }

        case kind
        when :variable
          klazz = ::DAP::Variable
          args = { name: safe(name, :to_s) { safe(name, :inspect) { '???' } }, value: value, type: type }
        when :evaluate
          klazz = ::DAP::EvaluateResponseBody
          args = { result: value, type: type }
        end

        if named.empty? && indexed.empty?
          args[:variablesReference] = 0
        else
          args[:variablesReference] = variable_refs << [thnum, frnum, kind, raw, named, indexed]
          args[:namedVariables] = named.size
          args[:indexedVariables] = indexed.size
        end

        klazz.new(args).validate!
      end

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
