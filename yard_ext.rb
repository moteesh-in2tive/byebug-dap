$pre_swizzle_run_verifier ||= YARD::Templates::Helpers::BaseHelper.instance_method(:run_verifier)
$pre_swizzle_linkify ||= YARD::Templates::Helpers::BaseHelper.instance_method(:linkify)
$external_linkify_re ||= /^(?:(?<kind>gem|std):(?<lib>\w+):|(?<kind>std):)?(?<scope>\w+(?:::\w+)*)(?<method>[.#]\w+)?$/

module YARD::Templates::Helpers::BaseHelper
  def run_verifier(list)
    $pre_swizzle_run_verifier.bind(self).call(list).reject do |obj|
      %w(Byebug::Context Byebug::Frame).include?(obj.path)
    end
  end

  def linkify(*args)
    name, text, = args
    link = $pre_swizzle_linkify.bind(self).call(*args)
    return link if !name.is_a?(String) || link.start_with?('<span')
    return link unless m = name.match($external_linkify_re)

    if m[:kind].nil? && m[:scope].start_with?('Protocol::')
      build_external_link('gitlab', 'ruby-dap', 'DAP::' + m[:scope][10..], m[:method], name, text) || link
    elsif !m[:kind].nil?
      build_external_link(m[:kind], m[:lib] || 'core', m[:scope], m[:method], name, text) || link
    else
      link
    end
  end

  def build_external_link(kind, lib, scope, method, name, text)
    text = "#{scope}#{method}" if text == name || text.nil?

    title = name
    if method
      title += ' (method)'
    else
      title += ' (module)'
    end

    url =
      case kind
      when 'std'
        'https://ruby-doc.org'
      when 'gem'
        'https://rubydoc.info/gems'
      when 'gitlab'
        'https://firelizzard.gitlab.io'
      else
        return nil
      end

    if kind == 'std' && lib != 'core'
      url += "/stdlib/libdoc/#{lib}/rdoc"
    else
      url += "/#{lib}"
    end

    unless kind == 'gem' && lib == 'byebug'
      url += "/#{scope.gsub(/::/, '/')}.html"

      place, fix =
        if kind == 'std'
          if method&.start_with?('.')
            [:pre, 'method-c']
          elsif method&.start_with?('#')
            [:pre, 'method-i']
          end
        else
          if method&.start_with?('.')
            [:post, 'class_method']
          elsif method&.start_with?('#')
            [:post, 'instance_method']
          end
        end

      if place == :pre
        url += "##{fix}-#{method[1..]}"
      elsif place == :post
        url += "##{method[1..]}-#{fix}"
      end
    end

    "<span class='object_link'><a target='_blank' href='#{url}' title='#{title}'>#{text}</a></span>"
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
