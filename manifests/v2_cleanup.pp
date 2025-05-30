# @summary Class to remove old configuration files
#
# @api private
#
# Private subclass to remove configurations utilized by v1 of this module
#
# @example
#   include event_notifier::v2_cleanup
class event_notifier::v2_cleanup {
  file { "${settings::confdir}/event_notifier.yaml":
    ensure => absent,
  }

  file { "${settings::confdir}/event_notifier_routes.yaml":
    ensure => absent,
  }
}
