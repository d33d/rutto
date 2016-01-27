#!/usr/bin/env perl
use Mojo::Base -strict;
use Mojo::IOLoop;
use Mojo::Asset::File;
use Mojo::Message::Request;
#use File::Path 'mkpath';

my $verbose = 0;

my %buffer;
Mojo::IOLoop->server(
  {port => 3000} => sub {
    my ($loop, $stream, $client) = @_;
    
    say "CLIENT: $client" if $verbose;
    print "\n";

    $stream->on(  
      read => sub {
        my ($stream, $chunk) = @_;
        
        say "ORA " . $chunk;
        # write chunk from client to server
        my $server = $buffer{$client}{connection};

        if (length $server) {
          $buffer{$client}{flow}->add_chunk("SERVER >>>>> CLIENT\n") if ($buffer{$client}{flow});
          $buffer{$client}{flow}->add_chunk($chunk) if ($buffer{$client}{flow});
          return Mojo::IOLoop->stream($server)->write($chunk) 
        }

        #print "New Client request\n";
        #Read connect request from client
        my $buffer = $buffer{$client}{client} .= $chunk;
        
        if ($buffer =~ /\x0d?\x0a\x0d?\x0a$/) {
          $buffer{$client}{client} = '';

          #### TLS
          if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
            my $address = $1;
            my $port    = $2 || 80;

            say "TLS";

            # Connection to server
            $buffer{$client}{connection} = Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $stream) = @_;

                # Connection to server failed
                if ($err) {
                  say "Connection error for $address:$port: $err";
                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }

                # Start forwarding data in both directions
                say "Forwarding to $address:$port";
                Mojo::IOLoop->stream($client)->write("HTTP/1.1 200 OK\x0d\x0a" . "Connection: keep-alive\x0d\x0a\x0d\x0a");
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );

                # Server closed connection
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($client);
                    delete $buffer{$client};
                  }
                );
              }
            );
          }
          
          else {  

            my $req = Mojo::Message::Request->new;
            $req->parse($buffer);

            my $host = $req->headers->host;
            say $host;

            say $req->method;
            say $req->headers->host;
            say $req->body;
      
            my ($address, $port) = split (':', $host);
            $port = 80 if (!defined $port || $port !~ m/^\d+$/);
            
            $buffer{$client}{host} = $host;
            $buffer{$client}{port} = $port;
              
            # Connection to server
            $buffer{$client}{flow} = Mojo::Asset::File->new(path => './flow/' . $address.'_'.$port.'_'.$client.'.flow');
            $buffer{$client}{flow}->cleanup(0);

            $buffer{$client}{connection} = Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $stream) = @_;
     
                # Connection to server failed
                if ($err) {
                  say "Connection error for $address:$port: $err" if ($verbose);
                  
                  $buffer{$client}{flow}->add_chunk("ERROR >>>>> ERROR\n");
                  $buffer{$client}{flow}->add_chunk("Connection error for $address:$port: $err\n");

                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }
     
                # Start forwarding data in both directions
                say "\n\n[****] CLIENT >>>>> SERVER $address:$port";
                
                $buffer{$client}{flow}->add_chunk("CLIENT >>>>> SERVER $address:$port\n");
                $buffer{$client}{flow}->add_chunk($req->to_string);
                
                $stream->write($req->to_string);

                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    if ($verbose) {
                      say "[*****] SERVER >>>>> CLIENT $address:$port";
                      say $chunk;
                    }

                    $buffer{$client}{flow}->add_chunk("SERVER >>>>> CLIENT $address:$port\n");
                    $buffer{$client}{flow}->add_chunk($chunk);
                    
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );
     
                # Server closed connection
                $stream->on(
                  close => sub {
                    #say "CLOSE CLIENT: " . $client;
                    Mojo::IOLoop->remove($client);
                    
                    $buffer{$client}{flow}->add_chunk("CLOSE >>>>> SERVER CLOSE\n") if ($buffer{$client}{flow});
                    delete $buffer{$client};
                  }
                );
              }
            );
          }
        }
      }
    );
    # Client closed connection
    $stream->on(
      close => sub {
        my $buffer = delete $buffer{$client};
        $buffer{$client}{flow}->add_chunk("CLOSE >>>>> CLIENT CLOSE\n") if ($buffer{$client}{flow});
        Mojo::IOLoop->remove($buffer->{connection}) if $buffer->{connection};
      }
    );

  }
);
 
print <<'EOF';
Now your RUTTO Proxy is on 127.0.0.1 port 3000.
EOF

unless (-d './flow') { mkdir './flow' or die "Cannot create dirctory: flow dir... please check!"; }

Mojo::IOLoop->start;
 
1;
