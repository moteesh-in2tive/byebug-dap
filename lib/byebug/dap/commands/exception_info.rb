module Byebug::DAP
  class Command::ExceptionInfo < ContextualCommand
    # "Retrieves the details of the exception that caused this event to be raised.

    register!

    def execute_in_context
      unless ex = @processor.last_exception
        respond! success: false, message: 'Not in a catchpoint context'
        return
      end

      class_name = safe(ex, [:class, :name]) { "Unknown" }

      respond! body: {
        exceptionId: class_name,
        description: safe(-> { "#{ex.message} (#{ex.class.name})" }, :call) { "*Error in evaluation*" },
        breakMode: ::DAP::ExceptionBreakMode::ALWAYS,
        details: details(ex),
      }
    end

    private

    def details(ex)
      class_name = safe(ex, [:class, :name]) { nil }
      type_name = class_name.split('::').last if class_name
      inner = safe(ex, :cause) { nil }

      {
        message: safe(ex, :message) { nil },
        typeName: type_name,
        fullTypeName: class_name,
        stackTrace: safe(ex, :backtrace) { [] }.join("\n"),
        innerException: inner.nil? ? [] : [details(inner)],
      }
    end
  end
end
