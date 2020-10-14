module Byebug::DAP
  class Command::Variables < Command
    # "Retrieves all child variables for the given variable reference.
    # "An optional filter can be used to limit the fetched children to either named or indexed children

    include ValueHelpers

    register!

    def execute
      started!

      thnum, frnum, named, indexed = resolve_variables_reference(args.variablesReference)

      case args.filter
      when 'named'
        indexed = []
      when 'indexed'
        named = []
      end

      vars = named + indexed

      first = args.start || 0
      last = args.count ? first + args.count : vars.size
      last = vars.size unless last < vars.size

      variables = vars[first...last].map { |var, get| prepare_value_response(thnum, frnum, :variable, name: var) { get.call(var) } }

      respond! body: Protocol::VariablesResponseBody.new(variables: variables)
    end
  end
end
