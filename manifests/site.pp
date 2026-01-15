# Main manifest file for Puppet environment

# Default node configuration
node default {
  # Include hello_world module
  include hello_world

  # Ensure basic packages are managed
  include stdlib

  # Log a message
  notify { 'Puppet environment loaded':
    message => "Puppet environment successfully loaded on ${facts['fqdn']}",
  }
}

# You can add specific node configurations here
# node 'webserver.example.com' {
#   include apache
# }

# node 'dbserver.example.com' {
#   include mysql
# }
