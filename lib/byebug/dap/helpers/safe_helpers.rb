module Byebug
  module DAP
    module SafeHelpers
      def safe(target, method, *args, &block)
        if target.respond_to?(method)
          target.__send__(method, *args)
        else
          yield
        end
      rescue StandardError => e
        log "\n! #{e.message} (#{e.class})", *e.backtrace if Debug.evaluate
        block.parameters.empty? ? yield : yield(e)
      end
    end
  end
end
