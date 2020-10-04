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
        target.__send__(method, *args)
      rescue StandardError
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
        indexed = [] # TODO indexed items
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
