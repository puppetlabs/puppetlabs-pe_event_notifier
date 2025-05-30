require 'puppet/indirector/facts/yaml'
require 'puppet/util/profiler'
require File.dirname(__FILE__) + '/../../util/event_notifier.rb'

# rubocop:disable Style/ClassAndModuleCamelCase
# event_notifier.rb
class Puppet::Node::Facts::Event_notifier < Puppet::Node::Facts::Yaml
  desc "Save facts to Splunk over HEC and then to yamlcache.
       It uses PuppetDB to retrieve facts for catalog compilation."

  include Puppet::Util::Event_notifier

  def get_trusted_info(node)
    trusted = Puppet.lookup(:trusted_information) do
      Puppet::Context::TrustedInformation.local(node)
    end
    trusted.to_h
  end

  def profile(message, metric_id, &block)
    message = 'Event notifier: ' + message
    arity = Puppet::Util::Profiler.method(:profile).arity
    case arity
    when 1
      Puppet::Util::Profiler.profile(message, &block)
    when 2, -2
      Puppet::Util::Profiler.profile(message, metric_id, &block)
    end
  end

  def save(request)
    # yaml cache goes first
    super(request)

    profile('splunk_facts#save', [:splunk, :facts, :save, request.key]) do
      host = request.instance.name.dup
      incoming_facts = request.instance.values.dup
      transaction_uuid = request.options[:transaction_uuid]

      hardcoded = [
        'os',
        'memory',
        'puppetversion',
        'system_uptime',
        'load_averages',
        'ipaddress',
        'fqdn',
      ]

      # lets ensure user provided fact names are downcased
      allow_list  = (settings['facts.allowlist'].map(&:downcase) + hardcoded).uniq
      block_list  = settings['facts.blocklist'].nil? ? [] : settings['facts.blocklist'].map(&:downcase)
      # lets rescue any hardcoded facts that have been added to the blocklist
      rescued_facts = block_list.select { |k| hardcoded.include?(k) }

      facts = if allow_list.include?('all.facts')
                unless rescued_facts.empty?
                  Puppet.warning "Rescued required facts - Please remove the following facts from event_notifier::facts_blocklist: #{rescued_facts}"
                end
                final_block = block_list.reject { |k| hardcoded.include?(k) }
                incoming_facts.reject { |k, _v| final_block.include?(k) }
              else
                incoming_facts.select { |k, _v| allow_list.include?(k) }
              end

      facts['trusted'] = get_trusted_info(request.node)
      facts['environment'] = request.options[:environment] || request.environment.to_s
      facts['producer'] = Puppet[:certname]
      facts['pe_console'] = pe_console
      facts['transaction_uuid'] = transaction_uuid

      event = {
        'host' => host,
        'sourcetype' => 'puppet:facts',
        'event' => facts
      }

      Puppet.info "Submitting facts to Splunk at #{get_splunk_url('facts')}"
      submit_request event
    rescue StandardError => e
      Puppet.err "Could not send facts to Splunk: #{e}\n#{e.backtrace}"
    end
  end
end
