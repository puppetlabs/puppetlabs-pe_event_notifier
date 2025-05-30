require File.dirname(__FILE__) + '/../util/event_notifier.rb'

Puppet::Reports.register_report(:event_notifier) do
  desc 'Submits just a report summary to Splunk HEC endpoint'
  # Next, define and configure the report processor.

  include Puppet::Util::Event_notifier
  def process
    # This prevents the processor from running if disabled
    return 0 if settings['disabled']

    # This prevents the processor from running when there are no changes to the report
    if settings['only_changes'] && (status != 'changed')
      Puppet.warning "Not submitting report to Splunk, report contains no changes! Status: #{status}"
      return 0
    end

    # now we can create the event with the timestamp from the report
    epoch = sourcetypetime(time, metrics['time']['total'])

    # pass simple metrics for report processing later
    #  STATES = [:skipped, :failed, :failed_to_restart, :restarted, :changed, :out_of_sync, :scheduled, :corrective_change]
    metrics = {
      'time' => {
        'config_retrieval' => self.metrics['time']['config_retrieval'],
        'fact_generation' => self.metrics['time']['fact_generation'],
        'catalog_application' => self.metrics['time']['catalog_application'],
        'total' => self.metrics['time']['total'],
      },
      'resources' => {
        'total' => self.metrics['resources']['total'],
      },
      'changes' => {
        'total' => self.metrics['changes']['total'],
      },
    }

    event = {
      'host' => host,
      'time' => epoch,
      'sourcetype' => 'puppet:summary',
      'event' => {
        'cached_catalog_status' =>  cached_catalog_status,
        'catalog_uuid' => catalog_uuid,
        'certname' => host,
        'code_id' => code_id,
        'configuration_version' => configuration_version,
        'corrective_change' => corrective_change,
        'environment' => environment,
        'job_id' => job_id,
        'metrics' => metrics,
        'noop' => noop,
        'noop_pending' => noop_pending,
        'pe_console' => pe_console,
        'producer' => Puppet[:certname],
        'puppet_version' => puppet_version,
        'report_format' => report_format,
        'server_used' => server_used,
        'status' => status,
        'time' => (time + metrics['time']['total']).iso8601(3),
        'transaction_uuid' => transaction_uuid,
      },
    }

    include_logs = false

    if settings['include_logs_status']
      include_logs_status = settings['include_logs_status']
      if include_logs_status.include? status
        include_logs = true
      end
    end

    if settings['include_logs_catalog_failure'] && catalog_uuid.to_s.strip.empty?
      include_logs = true
    end

    if settings['include_logs_corrective_change'] && corrective_change
      include_logs = true
    end

    if include_logs
      event['event']['logs'] = logs
    end

    # the i'm tired way to prevent doing this twice
    add_resources = false

    if settings['include_resources_status']
      include_resources_status = settings['include_resources_status']
      if include_resources_status.include? status
        add_resources = true
      end
    end

    if settings['include_resources_corrective_change'] && corrective_change
      add_resources = true
    end

    if add_resources
      resource_events_hash = resource_statuses.select { |_k, v| v.events.count > 0 }
      # We may want to return this as a hash or an array. Splunk deals better
      # with arrays but we need to give people the choice so as to not break
      # existing reports
      event['event']['resource_events'] = if settings['summary_resources_format'] == 'array'
                                            resource_events_hash.map { |_k, v| v }
                                          else
                                            resource_events_hash
                                          end
    end

    Puppet.info "Submitting report to Splunk at #{get_splunk_url('summary')}"
    submit_request event

    if record_event
      store_event event
    end
  rescue StandardError => e
    Puppet.err "Could not send report to Splunk: #{e}\n#{e.backtrace}"
  end
end
