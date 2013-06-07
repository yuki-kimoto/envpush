use Envpush;
use Mojo::Base 'Mojolicious';

my $clients = {};

sub startup {
  my $self = shift;
  
  $self->plugin('INIConfig');
  
  my $r = $self->routes;
  
  $r->websocket('/echo' => sub {
    my $self = shift;
   
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
