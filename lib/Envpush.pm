use Envpush;
use Mojo::Base 'Mojolicious';

my $clients = {};

sub startup {
  my $self = shift;
  
  $self->plugin('INIConfig');
  
  my $r = $self->routes;

  my $start;
  my $file_check_id;
  my @commands;
  
  $r->websocket('/' => sub {
  
    unless ($start++) {
      $file_check_id = Mojo::IOLoop->recurring(5 => sub {
        
      });
    }
    
    my $id = sprintf "%s", $self->tx;
    $clients->{$id} = $self->tx;
    
    $self->on(message => sub {
      my ($self, $msg) = @_;
      
      for my $id (keys %$clients) {
        $clients->{$id}->send();
      }
    });
  });
}

1;
