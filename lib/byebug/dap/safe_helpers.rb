module Byebug
  module DAP
    module SafeHelpers
      module Scalar
        def ===(value)
          case value
          when nil, true, false
            return true
          when ::String, ::Symbol, ::Numeric
            return true
          when ::Time, ::Range
            true
          end

          return true if defined?(::Date) && ::Date === value
          return true if defined?(::DateTime) && ::DateTime === value

          false
        end
      end

      def safe(target, method, *args)
        if target.respond_to?(method)
          target.__send__(method, *args)
        else
          yield
        end
      rescue StandardError => e
        STDERR.puts "\n! #{e.message} (#{e.class})", *e.backtrace if Debug.evaluate
        yield
      end

      def prepare_value(val)
        str = safe(val, :inspect) { safe(val, :to_s) { return yield } }
        cls = safe(val, :class) { nil }
        typ = safe(cls, :name) { safe(cls, :to_s) { nil } }

        scalar = safe(-> { Scalar === val }, :call) { true }
        return str, typ, [], [] if scalar

        named = safe(val, :instance_variables) { [] }
        named += safe(val, :class_variables) { [] }
        # named += safe(val, :constants) { [] }

        indexed = safe(-> {
          return (0...val.size).to_a if val.is_a?(Array)
          return val.keys if val.respond_to?(:keys) && val.respond_to?(:[])
          []
        }, :call) { [] }

        return str, typ, named, indexed
      end

      def prepare_value_from(target, method, *args, &block)
        val = safe(target, method, *args) { return yield }
        str, typ, named, indexed = prepare_value(val, &block)
        return val, str, typ, named, indexed
      end
    end
  end
end
