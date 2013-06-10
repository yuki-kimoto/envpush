use Envpush;
use Mojo::Base 'Mojolicious';
use Carp 'croak';
use Mojo::UserAgent;

sub startup {
  my $self = shift;
  my $app = $self;
  
  # Config
  my $config = $self->plugin('INIConfig');
  
  # Workers is always 1
  my $hypnotoad = $config->{hypnotoad};
  $hypnotoad->{workers} = 1;
  
  # Port
  my $is_parent = $hypnotoad->{type} eq 'parent';

  if ($is_parent) {
    $hypnotoad->{listen} ||= 'ws://*:10040';
  }
  else {
    $hypnotoad->{listen} ||= 'ws://*10041';
  }
  
  # Task directory
  my $task_dir = $self->home->rel_dir('task');
  unless (chdir $task_dir) {
    my $error = "Can't change directory $task_dir:$!";
    $app->log->error($error);
    croak $error;
  }

  my $r = $self->routes;
  
  # Parent
  if ($is_parent) {

    my $childs = {};
    
    $r->websocket('/' => sub {
      my $self = shift;
      
      # Child id
      my $cid = "$self";
      
      # Resist controller
      $clients->{$cid} = $self;
      
      # Receive
      $self->on(json => sub {
        my ($tx, $hash) = @_;
        
        my $remote_address = $tx->remote_address;
        
        if (my $message = $hash->{message}) {
          if ($hash->{error}) {
            $app->log->error("$message(From child $remote_address)");
          }
          else {
            $app->log->info("$message(From hild $remote_address)");
          }
        }
      });
      
      # Finish
      $self->on('finish' => sub {
        # Remove child
        delete $clients->{$cid};
      });
    });

    $r->websocket('/child' => sub {
      my $self = shift;
      
      $self->on(json => sub {
        my ($tx, $hash) = @_;
        
        # Send message to all childs
        for my $cid (keys %$childs) {
          $childs->{$cid}->send(json => $hash);
        }
      });
    );
  }
  
  # Child
  else {
    
    # Parent URL
    my $parent_host = $config->{parent}{host};
    croak "[parent]host is empty" unless defined $parent_host;
    
    my $parent_url = "ws://$parent_host";
    my $parent_port = $config->{parent}{port} || '10040';
    $parent_url .= ":$parent_port";

    # Rsync
    my $rsync
      = $conf->{child}{rsync} ? $conf->{child}{rsync} : $git->search_bin;
    if (!$rsync || ! -e $rsync) {
      $rsync ||= '';
      my $error = "Can't detect or found rsync command ($rsync)."
        . " set [child]rsync_path in config file";
      $app->log->error($error);
      croak $error;
    }

    # Execute task
    $r->websocket('/task' => sub {
      my $self = shift;
      
      $self->on(json => sub {
        my ($tx, $hash) = @_;
        my ($command, @args) = @{$hash->{command} || []};
        
        if ($command =~ /\./) {
          $app->log->error("Command can't contain dot: $command @args");
        }
        else {
          if (system($command, @args) == 0) {
            $app->log->info("Success command: $command @args");
          }
          else {
            $app->log->error("Can't execute command: $command @args");
          }
        }
        $self->finish;
      });
    );
    
    # Sync files
    $r->websocket('/sync' => sub {
      my $remote_host = $config->{parent}{host};
      my $ssh_user = $config->{parent}{ssh_user};
      my $ssh_port = $config->{parent}{ssh_port} || '23';
      my $parent_files = "$ssh_user@$remote_host:$task_dir";
      
      my @cmd = ($rsync, '-e', "ssh -p $ssh_port", '-a', $parent_file, '.');
      if (system(@cmd) == 0) {
        $app->log->info("Success rsync command: $command @args");
      }
      else {
        $app->log->error("Can't rsync execute command: $command @args");
      }
    });
        
    # Connect to parent
    my $connect_cb;
    $connect_cb = sub {
      my $ua = Mojo::UserAgent->new;
      $ua->websocket($parent_url => sub {
        my ($ua, $tx) = @_;
        
        unless ($tx->is_websocket) {
          my $error = "WebSocket handshake failed!";
          $app->log->error($error);
          Mojo::IOLoop->timer(30 => sub { $connect_cb->() });
          return;
        }
        
        my $local_address = $tx->local_address;
        my $local_port = $tx->local_port;
        
        $tx->on(json => sub {
          my ($tx, $hash) = @_;
          
          my $type = $hash->{type};
          if ($type eq 'task' || $tape eq 'sync') {
            my $ua = Mojo::UserAgent->new;
            
            $ua->websocket("ws://$local_address:$local_port/$type" => sub {
              my $self = shift;

              # Receive
              $self->on(json => sub {
                my ($tx, $hash) = @_;
                
                if (my $message = $hash->{message}) {
                  if ($hash->{error}) {
                    $app->log->error("$message");
                  }
                  else {
                    $app->log->info("$message");
                  }
                  $tx->send(json => $hash);
                }
              });
            });
          }
        });
      });
    };
    $connect_cb->();
  }
}

sub search_rsync {
  my $self = shift;
  
  # Search rsync bin
  my $env_path = $ENV{PATH};
  my @paths = split /:/, $env_path;
  for my $path (@paths) {
    $path =~ s#/$##;
    my $bin = "$path/rsync";
    if (-f $bin) {
      return $bin;
      last;
    }
  }
  
  my $local_bin = '/usr/local/bin/rsync';
  return $local_bin if -f $local_bin;
  
  my $bin = '/usr/bin/rsync';
  return $bin if -f $bin;
  
  return;
}

1;
