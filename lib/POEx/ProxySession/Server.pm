package POEx::ProxySession::Server;
BEGIN {
  $POEx::ProxySession::Server::VERSION = '1.102750';
}

#ABSTRACT: Hosts published sessions and routes proxy message

use MooseX::Declare;


class POEx::ProxySession::Server {
    with 'POEx::ProxySession::MessageSender';
    use POEx::ProxySession::Types(':all');
    use POEx::Types(':all');
    use MooseX::Types::Moose(':all');
    use Storable('thaw', 'nfreeze');
    use POE::Filter::Reference;
    use aliased 'POEx::Role::Event';


    has sessions =>
    (
        traits      => [ 'Hash' ],
        isa         => HashRef,
        lazy        => 1,
        default     => sub { {} },
        clearer     => 'clear_sessions',
        handles     => 
        {
            get_session        => 'get',
            set_session        => 'set',
            delete_session     => 'delete',
            count_sessions     => 'count',
            all_session_names  => 'keys',
            has_session        => 'exists',
        }
    );


    has delivered_store =>
    (
        traits      => [ 'Hash' ],
        isa         => HashRef,
        lazy        => 1,
        default     => sub { {} },
        clearer     => 'clear_delivereds',
        handles     => 
        {
            get_delivered        => 'get',
            set_delivered        => 'set',
            delete_delivered     => 'delete',
            count_delivereds     => 'count',
            all_delivered_keys   => 'keys',
            all_delivered_values => 'values',
            has_delivered        => 'exists',
        }
    );


    method handle_inbound_data(ProxyMessage $data, WheelID $id) is Event {
        if ($data->{type} eq 'publish')
        {
            $self->yield('publish_session', $data, $id);
        }
        elsif ($data->{type} eq 'rescind')
        {
            $self->yield('rescind_session', $data, $id);
        }
        elsif ($data->{type} eq 'listing')
        {
            $self->yield('get_listing', $data, $id);
        }
        elsif ($data->{type} eq 'subscribe')
        {
            $self->yield('subscribe_session', $data, $id);
        }
        elsif ($data->{type} eq 'deliver')
        {
            $self->yield('deliver_message', $data, $id);
        }
        elsif ($data->{type} eq 'result')
        {
            $self->yield('handle_delivered', $data, $id);
        }
        else
        {
            my $type = $data->{type};
            $self->yield
            (
                'send_result', 
                success     => 0,
                original    => $data, 
                wheel_id    => $id, 
                payload     => \"Unknown message type '$type'"
            );
        }
    }
    
    with 'POEx::Role::TCPServer';


    after _start(@args) is Event {
        $self->filter(POE::Filter::Reference->new());
    }


    method rescind_session(ProxyMessage $data, WheelID $id) is Event {
        my $payload = thaw($data->{payload});
        my $session = $payload->{session_alias};

        if(!$session)
        {
            $self->yield
            (
                'send_result', 
                success     => 0, 
                original    => $data, 
                wheel_id    => $id,
                payload     => \'Session alias is required', 
            );
        }
        elsif(!$self->has_session($session))
        {
            $self->yield
            (
                'send_result', 
                success     => 0, 
                original    => $data, 
                wheel_id    => $id,
                payload     => \"Session '$session' doesn't exist", 
            );
        }
        else
        {
            $self->delete_session($session);
            
            $self->yield
            (
                'send_result', 
                success     => 1, 
                original    => $data, 
                wheel_id    => $id
            );
        }
    }


    method publish_session(ProxyMessage $data, WheelID $id) is Event {
        my $payload = thaw($data->{payload});

        my $alias = $payload->{session_alias};
        my $name = $payload->{session_name};
        my $methods = $payload->{methods};

        if(!$alias)
        {
            $self->yield
            (
                'send_result', 
                success     => 0,
                original    => $data, 
                wheel_id    => $id, 
                payload     => \'Session alias must be defined'
            );
        }
        elsif($self->has_session($alias))
        {
            $self->yield
            (
                'send_result',
                success     => 0,
                original    => $data, 
                wheel_id    => $id, 
                payload     => \"Session '$alias' already exists"
            );
        }
        elsif(!$name)
        {
            $self->yield
            (
                'send_result', 
                success     => 0,
                original    => $data, 
                wheel_id    => $id, 
                payload     => \'Session name is required'
            );
        }
        else
        {
            $self->set_session($alias, { name => $name, methods => $methods, wheel => $id });
            
            $self->yield
            (
                'send_result', 
                success     => 1,
                original    => $data, 
                wheel_id    => $id,
                payload     => \$alias
            );
        }
    }


    method subscribe_session(ProxyMessage $data, WheelID $id) is Event {
        my $session_name = $data->{to};
        if(!$self->has_session($session_name))
        {
            $self->yield
            (
                'send_result', 
                success     => 0, 
                original    => $data, 
                wheel_id    => $id,
                payload     => \"Session '$session_name' doesn't exist", 
            );
            return;
        }

        my $result = { session => $session_name, methods => $self->get_session($session_name)->{methods} };

        $self->yield
        (
            'send_result', 
            success     => 1,
            original    => $data, 
            wheel_id    => $id, 
            payload     => $result
        );
    }


    method deliver_message(ProxyMessage $data, WheelID $id) is Event {
        my $session = $data->{to};
        
        if(!$self->has_session($session))
        {
            $self->yield
            (
                'send_result', 
                success     => 0, 
                original    => $data, 
                wheel_id    => $id,
                payload     => \"Session '$session' doesn't exist", 
            );
            return;
        }
        my $lookup = $self->get_session($session);
        
        $data->{to} = $lookup->{name};
        my $wheel_id = $lookup->{wheel};
        
        $self->set_delivered($data->{id}, $id);
        $self->get_wheel($wheel_id)->put($data);
    }

    method handle_delivered(ProxyMessage $data, WheelID $id) is Event {
        if($self->has_pending($data->{id}))
        {
            my $pending = $self->delete_pending($data->{id});
            $self->post($pending->{return_session}, $pending->{return_event}, $data, $id, $pending->{tag});
        }
        elsif($self->has_delivered($data->{id}))
        {
            my $to_id = $self->delete_delivered($data->{id});
            $self->get_wheel($to_id)->put($data);
        }
        else
        {
            warn q|Received an unexpected result message|;
        }
    }


    method get_listing(ProxyMessage $data, WheelID $id) is Event {
        $self->yield
        (
            'send_result', 
            success     => 1,
            original    => $data, 
            wheel_id    => $id, 
            payload     => [ $self->all_session_names ]
        );
    }
}

1;


=pod

=head1 NAME

POEx::ProxySession::Server - Hosts published sessions and routes proxy message

=head1 VERSION

version 1.102750

=head1 SYNOPSIS

class Flarg 
{
    with 'POEx::Role::SessionInstantiation';

    after _start(@args) is Event
    {
        POEx::ProxySession::Server->new
        (
            listen_ip   => '127.0.0.1',
            listen_port => 56789,
            alias       => 'Server',
            options     => { trace => 1, debug => 1 },
        );
    }
}

=head1 DESCRIPTION

POEx::ProxySession::Server is a lightweight network server that handles 
storage and listing of published sessions, and routing of proxied messages
between connected clients.

=head1 PROTECTED_ATTRIBUTES

=head2 sessions

This attribute is used to store the published sessions.

Access these sessions through the following methods:

The stored structure looks like the following:

    Session =>
    {
        name    => isa SessionAlias,
        methods => isa HashRef,
        id      => isa WheelID,
    }

=head2 delivered_store

delivered_store holds the wheel ids that are awaiting a response from some
other client. 

Access to these ids is provided through the following methods:

    handles     => 
    {
        get_delivered        => 'get',
        set_delivered        => 'set',
        delete_delivered     => 'delete',
        count_delivereds     => 'count',
        all_delivered_keys   => 'keys',
        all_delivered_values => 'values',
        has_delivered        => 'exists',
    }

=head1 PROTECTED_METHODS

=head2 handle_inbound_data

    (ProxyMessage $data, WheelID $id) is Event

Our implementation of handle_inbound_data expects a ProxyMessage as data. Here 
is where the handling and routing of messages lives. The following types of 
messages are handled here: publish, rescind, listing, subscribe, deliver, and
result. 

=head2 rescind_session

    (ProxyMessage $data, WheelID $id) is Event

This handles rescinding of a published session. No payload on success.

=head2 publish_session

    (ProxyMessage $data, WheelID $id) is Event

This method handles session publication. Payload on success is the session 
alias

=head2 subscribe_session

    (ProxyMessage $data, WheelID $id) is Event

This method handles subscription requests. Payload on success is a hashref:

    Payload =>
    {
        session => isa SessionAlias,
        methods => HashRef,
    }

=head2 deliver_message

    (ProxyMessage $data, WheelID $id) is Event

This method does message delivery by doing a lookup of the alias to the real
session name, and rewriting the message header to point to that session, then
sends it on to that session's connection. Sets a delivered message.

=head2 handle_delivered

    (ProxyMessage $data, WheelID $id) is Event

This method handles result messages from delivered messages. All messages that 
go through the system are expected to return a result message indicating 
success or failure.

=head2 get_listing

    (ProxyMessage $data, WheelID $id) is Event

This method handles listing requests from clients. Should always succeed.
Payload is an ArrayRef[SessionAlias].

=head1 PRIVATE_METHODS

=head2 after _start

    (@args) is Event

The _start method is advised to hardcode the filter to use as a 
POE::Filter::Reference instance.

=head1 AUTHOR

Nicholas Perez <nperez@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Nicholas Perez.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__
