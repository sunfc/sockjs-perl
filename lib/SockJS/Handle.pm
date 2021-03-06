package SockJS::Handle;

use strict;
use warnings;

use AnyEvent::Handle;

sub new {
    my $class = shift;
    my (%params) = @_;

    my $fh = delete $params{fh};

    my $self = {handle => AnyEvent::Handle->new(fh => $fh), %params};
    bless $self, $class;

    $self->{heartbeat_timeout} ||= 10;

    #$fh->autoflush;

    #$self->{handle}->no_delay(1);
    $self->{handle}->on_eof(sub   { warn "Unhandled handle eof" });
    $self->{handle}->on_error(sub { warn "Unhandled handle error: $_[2]" });

    # This is needed for the correct EOF handling
    $self->{handle}->on_read(sub { });

    return $self;
}

sub fh { $_[0]->{handle}->fh }

sub on_heartbeat {
    my $self = shift;
    my ($cb) = @_;

    $self->{handle}->wtimeout($self->{heartbeat_timeout});
    $self->{handle}->on_wtimeout($cb);

    return $self;
}

sub on_read {
    my $self = shift;
    my ($cb) = @_;

    $self->{handle}->on_read(
        sub {
            my $handle = shift;

            $handle->push_read(
                sub {
                    $cb->($self, $_[0]->rbuf);
                }
            );
        }
    );

    return $self;
}

sub on_eof {
    my $self = shift;
    my ($cb) = @_;

    $self->{handle}->on_eof(
        sub {
            $cb->($self);
        }
    );

    return $self;
}

sub on_error {
    my $self = shift;
    my ($cb) = @_;

    $self->{handle}->on_error(
        sub {
            $cb->($self);
        }
    );

    return $self;
}

sub write {
    my $self = shift;
    my ($chunk, $cb) = @_;

    my $handle = $self->{handle};
    return unless $handle;

    $handle->push_write($chunk);

    if ($cb) {
        $handle->on_drain(
            sub {
                my $handle = shift;

                $handle->on_drain(undef);

                $cb->($self);
            }
        );
    }

    return $self;
}

sub close {
    my $self = shift;

    my $handle = delete $self->{handle};
    unless ($handle) {
        warn 'Handle is already closed';
        return;
    }

    $handle->wtimeout(0);

    $handle->on_drain;
    $handle->on_error;

    $handle->on_drain(
        sub {
            if ($_[0]->fh) {
                shutdown $_[0]->fh, 1;
                close $handle->fh;
            }

            $_[0]->destroy;
            undef $handle;
        }
    );

    return $self;
}

1;
