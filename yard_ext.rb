$pre_swizzle_run_verifier ||= YARD::Templates::Helpers::BaseHelper.instance_method(:run_verifier)

module YARD::Templates::Helpers::BaseHelper
  def run_verifier(list)
    $pre_swizzle_run_verifier.bind(self).call(list).reject do |obj|
      %w(Byebug::Context Byebug::Frame).include?(obj.path)
    end
  end
end
