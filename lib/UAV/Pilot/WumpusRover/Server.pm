package UAV::Pilot::WumpusRover::Server;
use v5.14;
use Moose;
use namespace::autoclean;
use IO::Socket::INET ();
use UAV::Pilot::WumpusRover::PacketFactory;
use UAV::Pilot::WumpusRover::Server::Backend;
use Time::HiRes ();
use Errno qw(:POSIX);

use constant BUF_LENGTH => 1024;
use constant SLEEP_LOOP_US => 1_000_000 / 100; # In microseconds

our $VERSION = 0.1;


has 'listen_port' => (
    is      => 'ro',
    isa     => 'Int',
    default => 49_000,
);
has 'backend' => (
    is  => 'ro',
    isa => 'UAV::Pilot::WumpusRover::Server::Backend',
);
has '_socket' => (
    is  => 'rw',
    isa => 'Maybe[IO::Socket::INET]',
);
has 'ch1_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch1_max',
);
has 'ch1_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch1_min',
);
has 'ch2_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 90,
    writer  => '_set_ch2_max',
);
has 'ch2_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -90,
    writer  => '_set_ch2_min',
);
has 'ch3_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch3_max',
);
has 'ch3_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch3_min',
);
has 'ch4_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch4_max',
);
has 'ch4_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch4_min',
);
has 'ch5_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch5_max',
);
has 'ch5_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch5_min',
);
has 'ch6_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch6_max',
);
has 'ch6_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch6_min',
);
has 'ch7_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch7_max',
);
has 'ch7_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch7_min',
);
has 'ch8_max' => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
    writer  => '_set_ch8_max',
);
has 'ch8_min' => (
    is      => 'ro',
    isa     => 'Int',
    default => -100,
    writer  => '_set_ch8_min',
);

with 'UAV::Pilot::Server';
with 'UAV::Pilot::Logger';


sub start_listen_loop
{
    my ($self) = @_;
    $self->_init_socket;

    my $CONTINUE = 1;
    while($CONTINUE) {
        if(! $self->_read_packet ) {
            # If we didn't read a packet, sleep for a while 
            Time::HiRes::usleep( $self->SLEEP_LOOP_US );
        }
    }

    return 1;
}

sub process_packet
{
    my ($self, $packet) = @_;
    my $backend = $self->backend;

    my $process = sub {
        if( $backend->process_packet($packet, $self) ) {
            my $ack = $self->_build_ack_packet( $packet );
            $self->_send_packet( $ack );           
        }
    };

    if(! $backend->started) {
        if( $packet->isa(
            'UAV::Pilot::WumpusRover::Packet::RequestStartupMessage' )) {
            $process->();
        }
        else {
            $self->_logger->warn( 'Recieved packet of type "' . ref( $packet )
                . '", but we need a RequestStartupMessage first' );
        }
    }
    else {
        $process->();
    }

    return 1;
}

sub _read_packet
{
    my ($self) = @_;
    my $logger = $self->_logger;
    my $return = 1;
    $logger->info( 'Received packet' );

    my $buf = undef;
    my $len = read( $self->_socket, $buf, $self->BUF_LENGTH );
    if( defined($len) && ($len > 0) ) {
        my $len = length $buf;
        $logger->info( "Read $len bytes" );
        my $packet = eval {
            my $packet = UAV::Pilot::WumpusRover::PacketFactory
                ->read_packet( $buf );
            $logger->info( 'Processing message ID: '
                . $packet->message_id . ' (type: ' . ref($packet) . ')' );
            $self->process_packet( $packet );
        };
        if( ref($@) ) {
            if( $@->isa( 'UAV::Pilot::ArdupilotPacketException::Badheader' ) ) {
                $self->_logger->warn(
                    'Bad header in packet: [' . $@->got_header . ']' );
            }
            elsif( $@->isa(
                'UAV::Pilot::ArdupilotPacketException::BadChecksum'
            )) {
                $self->_logger->warn( 'Bad checksum in packet' );
                $self->_logger->warn( 'Expected checksum: '
                    . $@->expected_checksum1 . ', ' . $@->expected_checksum2 );
                $self->_logger->warn( 'Got checksum: '
                    . $@->got_checksum1 . ', ' . $@->got_checksum2 );
            }
            else {
                my $is_ref = ref $@;
                $self->_logger->warn( 'Got exception while processing packet: '
                    . $is_ref ? $is_ref : $@ );
                $@->rethrow if $is_ref;
            }
        }
        elsif( $@ ) {
            die "Error processing packet: $@\n";
        }
    }
    elsif(! defined $len) {
        # Possible error
        if($!{EAGAIN} || $!{EWOULDBLOCK}) {
            $logger->info( 'No data to read' );
        }
        else {
            UAV::Pilot::IOException->throw({
                error => $!,
            });
        }
    }
    else {
        $return = 0;
        $logger->info( "No data to read" );
    }

    return $return;
}

sub _build_ack_packet
{
    my ($self, $packet) = @_;

    my $ack = UAV::Pilot::WumpusRover::PacketFactory->fresh_packet( 'Ack' );
    $ack->message_received_id( $packet->message_id );
    $ack->checksum_received1( $packet->checksum1 );
    $ack->checksum_received2( $packet->checksum2 );

    return $ack;
}

sub _send_packet
{
    my ($self, $packet) = @_;
    # TODO
    return 1;
}

sub _init_socket
{
    my ($self) = @_;
    $self->_logger->info( 'Starting listener on UDP port '
        . $self->listen_port );

    my $socket = IO::Socket::INET->new(
        Proto     => 'udp',
        LocalPort => $self->listen_port,
        Blocking  => 0,
    ) or UAV::Pilot::IOException->throw({
        error => 'Could not open socket: ' . $!,
    });
    $self->_socket( $socket );

    $self->_logger->info( 'Done starting listener' );
    return 1;
}

sub _map_value
{
    my ($self, $in_min, $in_max, $out_min, $out_max, $input) = @_;
    return 0 if $in_max - $in_min == 0; # Avoid divide-by-zero error
    my $output = ($input - $in_min) / ($in_max - $in_min)
        * ($out_max - $out_min) + $out_min;

    return $output;
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__


=head1 NAME

    UAV::Pilot::WumpusRover::Server

=head1 SYNOPSIS

    my $backend = UAV::Pilot::WumpusRover::Server::Backend::RaspberryPiI2C->new;
    my $server = UAV::Pilot::WumpusRover::Server->new({
        backend => $backend,
    });
    $server->start_listen_loop;

=head1 DESCRIPTION

A server for running the WumpusRover.  Listens on specified UDP port, 
defaulting to C<<UAV::Pilot::WumpusRover->DEFAULT_PORT>>.

=head1 METHODS

=head2 start_listen_loop

Starts listening on the UDP port.  Loops indefinitely.

=head2 process_packet

    process_packet( $packet )

Does the right thing with C<$packet> (a C<UAV::Pilot::WumpusRover::Packet> 
object).

=head2 ch*_min() and ch*_max()

The channel min/max values that you can set.  Channels are numbered 1 through 8.

Note that these are the min/max values that are input to the server.  The 
values output by the backend is set by the backend.

=head1 PROTECTED METHODS

=head2 _set_ch*_min( $value ) and _set_ch*_max( $value )

Sets the raw min/max value for the associated channel number.  Channels are 
numbered 1 through 8.

=head2 _map_value

    _map_value(
        $in_min, $in_max,
        $out_min, $out_max,
        $input,
    )

Given the input min/max settings, maps the input number to an equivalent 
output between the output min/max.  For instance:

    $self->_map_value(
        0, 10,
        0, 30,
        5,
    );

Would return 15.

Note that this returns 0 if C<$in_max - $in_min == 0>, which avoids a 
divide-by-zero error.  This isn't correct behavior and will be fixed Soon(tm). 
The output min/max settings don't have this problem.

The primary use of this method is for backends to map the channel values held 
by the Server object into the output needed by the backend connection.

=cut
