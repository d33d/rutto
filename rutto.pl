#!/usr/bin/env perl
use Mojo::Base -strict;
use Mojo::Message::Request;
use Mojo::IOLoop;

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
        
        say $chunk;
        # write chunk from client to server
        my $server = $buffer{$client}{connection};
        return Mojo::IOLoop->stream($server)->write($chunk) if length $server;
        
        #print "New Client request\n";
        # Read connect request from client
        my $buffer = $buffer{$client}{client} .= $chunk;
        
        #say $buffer;

        my $req = Mojo::Message::Request->new;
        $req->parse($buffer);

        my $host = $req->headers->host;
        #say $host;

        #say $req->method;
        #say $req->headers->host;
        #say $req->body;
  
        my ($address, $port) = split (':', $host);
        $port = 80 if (!defined $port || $port !~ m/^\d+$/);
        
        $buffer{$client}{host} = $host;
        $buffer{$client}{port} = $port;
          
        # Connection to server
        $buffer{$client}{connection} = Mojo::IOLoop->client(
          {address => $address, port => $port} => sub {
            my ($loop, $err, $stream) = @_;
 
            # Connection to server failed
            if ($err) {
              say "Connection error for $address:$port: $err" if ($verbose);
              Mojo::IOLoop->remove($client);
              return delete $buffer{$client};
            }
 
            # Start forwarding data in both directions
            say "\n\n[****] CLIENT >>>>> SERVER $address:$port";
            $stream->write($req->to_string);

            ### TLS with CONNECT request....
            #Mojo::IOLoop->stream($client)->write("HTTP/1.1 200 OK\x0d\x0a" . "Connection: keep-alive\x0d\x0a\x0d\x0a");
            #Mojo::IOLoop->stream($server)->write($req->to_string);
            
            $stream->on(
              read => sub {
                my ($stream, $chunk) = @_;
                if ($verbose) {
                  say "[****] SERVER >>>>> CLIENT";
                  say $chunk;
                }
                Mojo::IOLoop->stream($client)->write($chunk);
              }
            );
 
            # Server closed connection
            $stream->on(
              close => sub {
                #say "CLOSE CLIENT: " . $client;
                Mojo::IOLoop->remove($client);
                delete $buffer{$client};
              }
            );
          }
        );

      }
    );

    # Client closed connection
    $stream->on(
      close => sub {
        my $buffer = delete $buffer{$client};
        #print "Client closed connection\n";
        Mojo::IOLoop->remove($buffer->{connection}) if $buffer->{connection};
      }
    );

  }
);
 
print <<'EOF';
Starting CONNECT proxy on port 3000.
Now use RUTTO as proxy "HTTP_PROXY=http://127.0.0.1:3000".
EOF
 
Mojo::IOLoop->start;
 
1;
