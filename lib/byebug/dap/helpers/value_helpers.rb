module Byebug::DAP
  module ValueHelpers
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
        klazz = ::DAP::Variable
        args = { name: safe(name, :to_s) { safe(name, :inspect) { '???' } }, value: value, type: type }
      when :evaluate
        klazz = ::DAP::EvaluateResponseBody
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
