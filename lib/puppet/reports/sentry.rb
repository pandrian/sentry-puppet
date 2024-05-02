require 'puppet'
require 'yaml'

begin
    require 'rubygems'
rescue LoadError => e
    Puppet.err "You need `rubygems` to send reports to Sentry"
end

begin
    require 'sentry-ruby'
rescue LoadError => e
    Puppet.err "You need the `sentry-ruby` gem installed on the puppetmaster to send reports to Sentry"
end

Puppet::Reports.register_report(:sentry) do
    # Description
    desc = 'Puppet reporter designed to send failed runs to a Sentry server'

    # Those are the log levels used by Puppet::Util::Log
    # @levels = [:debug,:info,:notice,:warning,:err,:alert,:emerg,:crit]
    # (https://github.com/puppetlabs/puppet/blob/3f1bbd2ec31bc7be8a7626c23de8089ee638bad4/lib/puppet/util/log.rb#L16)
    # Those are the log levels we want to have alerts for:
    # Nothing that is less than :info should go to Sentry
    ALERT_ON = [:warning,:err,:alert,:emerg,:crit]

    # Load the config else error
    # The file sentry.yaml should be in the root of the environment
    config_path = File.join([File.dirname(Puppet.settings[:config]), "sentry.yaml"])

    unless File.exist?(config_path)
        raise(Puppet::ParseError, "Sentry config " + config_path + " doesn't exist")
    end

    CONFIG = YAML.load_file(config_path)

    # Process an event
    def process
        # We only care if the run failed
        if self.status != 'failed'
            return
        end

        # Check the config contains what we need
        if not CONFIG[:sentry_dsn]
            raise(Puppet::ParseError, "Sentry did not contain a dsn")
        end

         if self.respond_to?('environment')
             @environment = self.environment
         else
             @environment = 'production'
         end

         if self.respond_to?(:host)
             @host = self.host
         end


        if self.respond_to?(:puppet_version)
          @puppet_version = self.puppet_version
        end

        if self.respond_to?(:status)
          @status = self.status
        end

        # Initialize Sentry with DSN and current environment
        Sentry.init do |config|
            config.dsn = CONFIG[:sentry_dsn]
            config.environment = @environment
        end

        # Get the important looking stuff to Sentry
        self.logs.each do |log|
            if ALERT_ON.include?(log.level)
                Sentry.capture_message(log.message, {
                    server_name: @host,
                    tags: {
                        'status' => @status,
                        'version' => @puppet_version
                    },
                    extra: {
                        'source' => log.source,
                        'line' => log.line,
                        'file' => log.file
                    }
                })
            end
        end
    end
end
