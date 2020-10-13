$pre_swizzle_run_verifier ||= YARD::Templates::Helpers::BaseHelper.instance_method(:run_verifier)

module YARD::Templates::Helpers::BaseHelper
  def run_verifier(list)
    $pre_swizzle_run_verifier.bind(self).call(list).reject do |obj|
      %w(Byebug::Context Byebug::Frame).include?(obj.path)
    end
  end
end


class CommandExecuteHandler < YARD::Handlers::Ruby::Base
  handles :class

  def process
    case "#{namespace.path}::#{statement[0].source}"
    when 'Byebug::DAP::Command'
      register ClassObject.new(namespace, 'Command') do |cls|
        meth = MethodObject.new(cls, 'execute')
        meth.source = "def execute\n  raise NotImplementedError\nend"
        meth.signature = "def execute"
        meth.docstring = "Execute the command."
        meth.add_tag(YARD::Tags::Tag.new(:abstract, 'Must be overridden.'))
      end

    when 'Byebug::DAP::ContextualCommand'
      register ClassObject.new(namespace, 'ContextualCommand') do |cls|
        meth = MethodObject.new(cls, 'execute_in_context')
        meth.source = "def execute_in_context\n  raise NotImplementedError\nend"
        meth.signature = "def execute_in_context"
        meth.docstring = "Execute the command in the context's thread."
        meth.add_tag(YARD::Tags::Tag.new(:abstract, 'Must be overridden.'))
      end
    end
  end
end
