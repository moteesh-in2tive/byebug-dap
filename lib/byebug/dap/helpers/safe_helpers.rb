module Byebug
  module DAP
    # Methods to safely execute methods.
    # @api private
    module SafeHelpers
      # Safely execute `method` on `target` with `args`.
      # @param target the receiver
      # @param method [Symbol] the method name
      # @param args [Array] the method arguments
      # @yield called on error
      # @yieldparam ex [StandardError] the execution error
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
