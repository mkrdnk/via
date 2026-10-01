module Via::TLS
  module ContextBuilder
    {% if flag?(:without_openssl) %}
      def self.build(config : Configuration::TLS?) : Nil
        if config
          raise Configuration::Error.new(
            "TLS is unavailable because Via was built without OpenSSL"
          )
        end
      end
    {% else %}
      def self.build(config : Configuration::TLS?) : OpenSSL::SSL::Context::Server?
        return unless config

        context = OpenSSL::SSL::Context::Server.new
        context.certificate_chain = config.cert
        context.private_key = config.key
        context
      rescue ex : OpenSSL::Error
        raise Configuration::Error.new("Could not load TLS certificate or key: #{ex.message}")
      end
    {% end %}
  end
end
