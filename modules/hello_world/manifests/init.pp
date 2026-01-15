# hello_world
#
# A simple demonstration Puppet module
#
# @summary Manages a hello world file and message
#
# @example
#   include hello_world
class hello_world {
  # Create a hello world file
  file { '/tmp/hello_world.txt':
    ensure  => file,
    content => "Hello World from Puppet!\nManaged by g10k and GitHub Actions\nNode: ${facts['fqdn']}\nEnvironment: ${environment}\n",
    mode    => '0644',
  }

  # Display a notification
  notify { 'hello_world_loaded':
    message => 'Hello World module has been applied successfully!',
  }
}
