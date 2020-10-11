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
        description: exception_description(ex),
        breakMode: ::DAP::ExceptionBreakMode::ALWAYS,
        details: details(ex, '$!'),
      }
    end

    private

    def details(ex, eval_name)
      class_name = safe(ex, [:class, :name]) { nil }
      type_name = class_name.split('::').last if class_name
      inner = safe(ex, :cause) { nil }

      {
        message: safe(ex, :message) { nil },
        typeName: type_name,
        fullTypeName: class_name,
        evaluateName: eval_name,
        stackTrace: safe(ex, :backtrace) { [] }.join("\n"),
        innerException: inner.nil? ? [] : [details(inner, "#{eval_name}.#{cause}")],
      }
    end
  end
end
