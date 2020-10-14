module Byebug::DAP
  # Methods to prepare values for DAP responses.
  # @api private
  module ValueHelpers
    # Safely inspect a value and retrieve its class name, class and instance
    # variables, and indexed members. {Scalar} values do not have variables or
    # members. Only {std:Array arrays} and {std:Hash hashes} have members.
    # @return `val.inspect`, `val.class.name`, variables, and members.
    def prepare_value(val)
      str = safe(val, :inspect) { safe(val, :to_s) { return yield } }
      cls = safe(val, :class) { nil }
      typ = safe(cls, :name) { safe(cls, :to_s) { nil } }

      scalar = safe(-> { Scalar === val }, :call) { true }
      return str, typ, [], [] if scalar

      named = safe(val, :instance_variables) { [] } || []
      named += safe(val, :class_variables) { [] } || []
      # named += safe(val, :constants) { [] }

      indexed = safe(-> {
        return (0...val.size).to_a if val.is_a?(Array)
        return val.keys if val.respond_to?(:keys) && val.respond_to?(:[])
        []
      }, :call) { [] }

      return str, typ, named, indexed
    end

    # Prepare a {Protocol::Variable} or {Protocol::EvaluateResponseBody} for a
    # calculated value. For global variables and evaluations, `thnum` and
    # `frnum` should be 0. Local variables and evaluations are
    # {Command#execute_on_thread executed on the specified thread}.
    # @param thnum [std:Integer] the thread number
    # @param frnum [std:Integer] the frame number
    # @param kind [std:Symbol] `:variable` or `:evaluate`
    # @param name [std:String] the variable name (ignored for evaluations)
    # @yield retrieves an variable or evaluates an expression
    def prepare_value_response(thnum, frnum, kind, name: nil, &block)
      err = nil
      raw = execute_on_thread(thnum, block) { |e| err = e; nil }

      if err.nil?
        value, type, named, indexed = prepare_value(raw) { |e| next exception_description(e), nil, [], [] }
      else
        type, named, indexed = nil, [], []
        if err.is_a?(CommandProcessor::TimeoutError)
          name = err.context.thread.name
          value = "*Thread ##{err.context.thnum} #{name ? '(' + name + ')' : ''} unresponsive*"
        else
          value = exception_description(err)
        end
      end

      case kind
      when :variable
        klazz = Protocol::Variable
        args = { name: safe(name, :to_s) { safe(name, :inspect) { '???' } }, value: value, type: type }
      when :evaluate
        klazz = Protocol::EvaluateResponseBody
        args = { result: value, type: type }
      end

      if named.empty? && indexed.empty?
        args[:variablesReference] = 0
      else
        args[:variablesReference] = @session.save_variables(thnum, frnum, kind, raw, named, indexed)
        args[:namedVariables] = named.size
        args[:indexedVariables] = indexed.size
      end

      klazz.new(args).validate!
    end
  end
end
