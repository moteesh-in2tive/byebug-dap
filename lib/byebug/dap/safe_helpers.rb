module Byebug
  module DAP
    module SafeHelpers
      def safe(target, method, *args)
        target.__send__(method, *args)
      rescue StandardError
        yield
      end

      def prepare_value(val)
        str = safe(val, :inspect) { safe(val, :to_s) { return yield } }
        cls = safe(val, :class) { nil }
        typ = safe(cls, :name) { safe(cls, :to_s) { nil } }

        return str, typ
      end

      def prepare_value_from(target, method, *args, &block)
        val = safe(target, method, *args) { return yield }
        prepare_value(val, &block)
      end
    end
  end
end
