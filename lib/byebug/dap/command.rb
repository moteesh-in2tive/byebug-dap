module Byebug::DAP
  # Implementation of a DAP command.
  # @abstract Subclasses must implement {#execute}
  class Command
    # The error message returned when a variable or expression cannot be evaluated.
    EVAL_ERROR = "*Error in evaluation*"

    include SafeHelpers

    # The DAP command assocated with the receiver.
    # @return [std:String]
    def self.command
      return @command_name if defined?(@command_name)

      raise "Not a command" if self == Byebug::DAP::Command
      raise "Not a command" unless self < Byebug::DAP::Command
      raise "Not a command" unless self.name.start_with?('Byebug::DAP::Command::')

      last = self.name.split('::').last
      @command_name = "#{last[0].downcase}#{last[1..]}"
    end

    # Register the receiver as a DAP command.
    def self.register!
      (@@commands ||= {})[command] = self
    end

    # Resolve the requested command. Calls {Session#respond!} indicating a
    # failed request if the command cannot be found.
    # @param session [Session] the debug session
    # @param request [Protocol::Request] the DAP request
    # @return [std:Class] the {Command} class
    def self.resolve!(session, request)
      cls = @@commands[request.command]
      return cls if cls

      session.respond! request, success: false, message: 'Invalid command'
    end

    # Resolve and execute the requested command. The command is {.resolve!
    # resolved}, {#initialize initialized}, and {#safe_execute safely executed}.
    # @param session [Session] the debug session
    # @param request [Protocol::Request] the DAP request
    # @param args [std:Array] additional arguments for {#initialize}
    # @return the return value of {#safe_execute}
    def self.execute(session, request, *args)
      return unless command = resolve!(session, request)

      command.new(session, request, *args).safe_execute
    end

    # Create a new instance of the receiver.
    # @param session [Session] the debug session
    # @param request [Protocol::Request] the DAP request
    def initialize(session, request)
      @session = session
      @request = request
    end

    # (see Session#log)
    def log(*args)
      @session.log(*args)
    end

    # Call {#execute} safely, handling any errors that arise.
    # @return the return value of {#execute}
    def safe_execute
      execute

    rescue InvalidRequestArgumentError => e
      message =
        case e.error
        when String
          e.error

        when :missing_argument
          "Argument is unspecified: #{e.scope}"

        when :missing_entry
          "Cannot locate #{e.scope} ##{e.value}"

        when :invalid_entry
          "Error resolving #{e.scope}: #{e.value}"

        else
          log "#{e.message} (#{e.class})", *e.backtrace
          "An internal error occured"
        end

      respond! success: false, message: message

    rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
      :disconnected

    rescue CommandProcessor::TimeoutError => e
      respond! success: false, message: "Debugger on thread ##{e.context.thnum} is not responding"

    rescue StandardError => e
      respond! success: false, message: "An internal error occured"
      log "#{e.message} (#{e.class})", *e.backtrace
    end

    private

    def event!(*args, **values)
      @session.event! *args, **values
      return
    end

    def respond!(*args, **values)
      raise "Cannot respond without a request" unless @request

      @session.respond! @request, *args, **values
      return
    end

    # Raises an error if the debugger is running
    # @api private
    # @!visibility public
    def stopped!
      return if !Byebug.started?

      respond! success: false, message: "Cannot #{@request.command} - debugger is already running"
    end

    # Raises an error unless the debugger is running
    # @api private
    # @!visibility public
    def started!
      return if Byebug.started?

      respond! success: false, message: "Cannot #{@request.command} - debugger is not running"
    end

    def args
      @request.arguments
    end

    def exception_description(ex)
      safe(-> { "#{ex.message} (#{ex.class.name})" }, :call) { EVAL_ERROR }
    end

    # Execute a code block on the specified thread, {SafeHelpers#safe safely}.
    # @param thnum [std:Integer] the thread number
    # @param block [std:Proc] the code block
    # @yield called on error
    # @yieldparam ex [std:Exception] the execution error
    # @api private
    # @!visibility public
    def execute_on_thread(thnum, block, &on_error)
      return safe(block, :call, &on_error) if thnum == 0 || @context&.thnum == thnum

      p = find_thread(thnum).processor
      safe(-> { p.execute(&block) }, :call, &on_error)
    end

    def find_thread(thnum)
      raise InvalidRequestArgumentError.new(:missing_argument, scope: 'thread ID') unless thnum

      ctx = Byebug.contexts.find { |c| c.thnum == thnum }
      raise InvalidRequestArgumentError.new(:missing_entry, value: thnum, scope: 'thread') unless ctx

      ctx
    end

    def find_frame(ctx, frnum)
      raise InvalidRequestArgumentError.new(:missing_entry, value: frnum, scope: 'frame') unless frnum < ctx.stack_size

      ::Byebug::Frame.new(ctx, frnum)
    end

    def resolve_frame_id(id)
      raise InvalidRequestArgumentError.new(:missing_argument, scope: 'frame ID') unless id

      entry = @session.restore_frame(id)
      raise InvalidRequestArgumentError.new(:missing_entry, value: id, scope: 'frame ID') unless entry

      thnum, frnum = entry
      ctx = find_thread(thnum)
      frame = find_frame(ctx, frnum)
      return frame, thnum, frnum
    end

    def resolve_variables_reference(ref)
      raise InvalidRequestArgumentError.new(:missing_argument, scope: 'variables reference') unless ref

      entry = @session.restore_variables(ref)
      raise InvalidRequestArgumentError.new(:missing_entry, value: ref, scope: 'variables reference') unless entry

      thnum, frnum, kind, *entry = entry

      case kind
      when :locals
        frame = find_frame(find_thread(thnum), frnum)
        named, indexed = entry[0], []
        get = ->(key) {
          return frame._self if key == :self
          return frame.context.processor.last_exception if key == :$!
          values ||= frame.locals
          values[key]
        }

      when :globals
        frame = find_frame(find_thread(thnum), frnum)
        named, indexed = entry[0], []
        get = ->(key) { frame._binding.eval(key.to_s) }

      when :variable, :evaluate
        value, named, indexed = entry
        get = ->(key) { value.instance_eval { binding }.eval(key.to_s) }
        index = ->(key) { value[key] }

      else
        raise InvalidRequestArgumentError.new(:invalid_entry, value: kind, scope: 'variable scope')
      end

      return thnum, frnum, named.map { |k| [k, get] }, indexed.map { |k| [k, index] }
    end

    def can_read_file!(path)
      path = File.realpath(path)
      return path if File.readable?(path)

      if File.exist?(path)
        respond! success: false, message: "Source file '#{path}' exists but cannot be read"
      else
        respond! success: false, message: "No source file available for '#{path}'"
      end

      return nil
    end

    def potential_breakpoint_lines(path)
      ::Byebug::Breakpoint.potential_lines(path)
    rescue ScriptError, StandardError => e
      yield(e)
    end

    def convert_breakpoint_condition(condition)
      return nil if condition.nil? || condition.empty?
      return nil unless condition.is_a?(String)
      return condition
    end

    def convert_breakpoint_hit_condition(condition)
      # Because of https://github.com/deivid-rodriguez/byebug/issues/739,
      # Breakpoint#hit_condition can't be set to nil.
      return :ge, 0 if condition.nil? || condition.empty?
      return :ge, 0 unless condition.is_a?(String)

      m = /^(?<op><|<=|=|==|===|=>|>|%)?\s*(?<value>[0-9]+)$/.match(condition)
      raise InvalidRequestArgumentError.new("'#{condition}' is not a valid hit condition") unless m

      v = m[:value].to_i
      case m[:op]
      when nil, '=', '==', '==='
        return :eq, v

      when '>'
        return :ge, v - 1

      when '>='
        return :ge, v

      when '%'
        return :mod, v

      else
        raise InvalidRequestArgumentError.new("Byebug does not support hit conditions using '#{m[:op]}'") unless m
      end
    end

    def find_or_add_breakpoint(verified, existing, source, pos)
      if bp = verified.find { |bp| bp.source == source && bp.pos == pos }
        return bp
      end

      if bp = existing.find { |bp| bp.source == source && bp.pos == pos }
        existing.delete(bp)
      else
        bp = Byebug::Breakpoint.add(source, pos.is_a?(String) ? pos.to_sym : pos)
      end

      verified << bp
      bp
    end
  end
end
