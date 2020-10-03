module Byebug
  module DAP
    class Interface
      @@debug = false

      def self.enable_debug
        @@debug = true
      end

      attr_reader :socket

      def initialize(socket)
        @socket = socket
      end

      def puts(message)
        STDERR.puts "> #{message.to_wire}" if @@debug
        socket.write ::DAP::Encoding.encode(message)
      end

      def gets
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
            name: ctx.thread.name || "Thread ##{ctx.thnum}" )}
      end

      def find_thread(id)
        return yield(:missing_argument, 'thread ID') unless thnum

        ctx = Byebug.contexts.find { |c| c.thnum == id }
        return yield(:missing_thread, id) unless ctx

        ctx
      end

      def resolve_frame_id(id)
        entry = frame_ids[id]
        return yield(:missing_entry, id) unless entry

        thnum, frnum = entry
        ctx = Byebug.contexts.find { |c| c.thnum == thnum }
        return yield(:missing_thread, thnum) unless ctx
        return yield(:missing_frame, frnum) unless frnum < ctx.stack_size

        return ::Byebug::Frame.new(ctx, frnum), thnum, frnum
      end

      def frames(thnum, at:, count:)
        ctx = find_thread(thnum) { |err, v| return yield(err, v) }

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
            line: frame.line)
        end

        return frames, ctx.stack_size
      end

      def resolve_variable_ref(ref)
        entry = variable_refs[ref]
        return yield(:missing_entry, ref) unless entry

        thnum, frnum, kind, *entry = entry
        ctx = find_thread(thnum) { |err, v| return yield(err, v) }
        return yield(:missing_frame, frnum) unless frnum < ctx.stack_size

        frame = ::Byebug::Frame.new(ctx, frnum)

        case kind
        when :arguments, :locals
          return kind, entry[0], ->(key) {
            values ||= frame.locals
            values[key]
          }
        when :globals
          return kind, entry[0], ->(key) { frame._binding.eval(key.to_s) }
        else
          return yield(:invalid_entry, "Unknown variable scope #{kind}")
        end
      end

      def scopes(frameId, &block)
        return yield(:missing_argument, 'frame ID') unless frameId

        frame, thnum, frnum = resolve_frame_id(frameId, &block)
        return unless frame

        scopes = []

        args = frame_arg_names(frame).sort
        unless args.empty?
          scopes << ::DAP::Scope.new(
            name: 'Arguments',
            presentationHint: 'arguments',
            variablesReference: variable_refs << [thnum, frnum, :arguments, args],
            namedVariables: args.size,
            indexedVariables: 0,
            expensive: false)
        end

        locals = frame_local_names(frame, args: args).sort
        unless locals.empty?
          scopes << ::DAP::Scope.new(
            name: 'Locals',
            presentationHint: 'locals',
            variablesReference: variable_refs << [thnum, frnum, :locals, locals],
            namedVariables: locals.size,
            indexedVariables: 0,
            expensive: false)
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
        end

        scopes
      end

      def variables(varRef, at:, count:, filter: nil, &block)
        return yield(:missing_argument, 'variables reference') unless varRef

        kind, scope, get = resolve_variable_ref(varRef, &block)
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
          value = get.call(var)
          ::DAP::Variable.new(
            name: var,
            value: value,
            type: value.class.name)
        end
      end

      def evaluate(frameId, expression, &block)
        frame, thnum, frnum = resolve_frame_id(frameId, &block)
        return unless frame

        # TODO support structured values
        value = frame._binding.eval(expression)
        ::DAP::EvaluateResponseBody.new(
          result: value,
          type: value.class.name)
      end

      private

      def frame_ids
        @frame_ids ||= Handles.new
      end

      def variable_refs
        @variable_refs ||= Handles.new
      end

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
