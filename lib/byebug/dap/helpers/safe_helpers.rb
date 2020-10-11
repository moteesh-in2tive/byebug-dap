module Byebug
  module DAP
    module SafeHelpers
      def safe(target, method, *args, &block)
        if method.is_a?(Array) && args.empty?
          method.each { |m| target = target.__send__(m) }
          target
        else
          target.__send__(method, *args)
        end
      rescue StandardError => e
        log "\n! #{e.message} (#{e.class})", *e.backtrace if Debug.evaluate
        block.parameters.empty? ? yield : yield(e)
      end
    end
  end
end
