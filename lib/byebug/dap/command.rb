module Byebug::DAP
  class Command
    include SafeHelpers

    def self.command
      return @command_name if defined?(@command_name)

      raise "Not a command" if self == Byebug::DAP::Command
      raise "Not a command" unless self < Byebug::DAP::Command
      raise "Not a command" unless self.name.start_with?('Byebug::DAP::Command::')

      last = self.name.split('::').last
      @command_name = "#{last[0].downcase}#{last[1..]}"
    end

    def self.register!
      (@@commands ||= {})[command] = self
    end

    def self.resolve!(session, request)
      cls = @@commands[request.command]
      return cls if cls

      session.respond! request, success: false, message: 'Invalid command'
    end

    def self.execute(session, request, *args)
      return unless command = resolve!(session, request)

      command.new(session, request, *args).safe_execute
    end

    def initialize(session, request)
      @session = session
      @request = request
    end

    def log(*args)
      @session.log(*args)
    end

    def safe_execute
      execute

    rescue InvalidRequestArgumentError => e
      case e.error
      when :missing_argument
        respond! success: false, message: "Missing #{e.scope}"

      when :missing_entry
        respond! success: false, message: "Invalid #{e.scope} #{e.value}"

      when :missing_thread
        respond! success: false, message: "Cannot locate thread ##{e.value}"

      when :missing_frame
        respond! success: false, message: "Cannot locate frame ##{e.value}"

      when :invalid_entry
        respond! success: false, message: "Error resolving #{e.scope}: #{e.value}"

      else
        respond! success: false, message: "An internal error occured"
        log "#{e.message} (#{e.class})", *e.backtrace
      end

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

    def stopped!
      return if !Byebug.started?

      respond! success: false, message: "Cannot #{@request.command} - debugger is already running"
    end

    def started!
      return if Byebug.started?

      respond! success: false, message: "Cannot #{@request.command} - debugger is not running"
    end

    def args
      @request.arguments
    end

    def execute_on_thread(thnum, block, &on_error)
      return safe(block, :call, &on_error) if thnum == 0 || @context&.thnum == thnum

      p = find_thread(thnum).__send__(:processor)
      safe(-> { p.execute(&block) }, :call, &on_error)
    end

    def find_thread(thnum)
      raise InvalidRequestArgumentError.new(:missing_argument, scope: 'thread ID') unless thnum

      ctx = Byebug.contexts.find { |c| c.thnum == thnum }
      raise InvalidRequestArgumentError.new(:missing_thread, value: thnum, scope: 'thread ID') unless ctx

      ctx
    end

    def find_frame(ctx, frnum)
      raise InvalidRequestArgumentError.new(:missing_frame, value: frnum) unless frnum < ctx.stack_size

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
  end
end
