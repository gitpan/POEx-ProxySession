package POEx::ProxySession::Client;
BEGIN {
  $POEx::ProxySession::Client::VERSION = '1.102750';
}

#ABSTRACT: Proxies remote, published Sessions, or publishes, local Sessions for subscription

use MooseX::Declare;


class POEx::ProxySession::Client {
    with 'POEx::ProxySession::MessageSender';
    use POEx::ProxySession::Types(':all');
    use POEx::Types(':all');
    use POE::Filter::Reference;
    use MooseX::Types;
    use MooseX::Types::Moose(':all');
    use MooseX::Types::Structured('Optional','Dict','Tuple');
    use Moose::Util('does_role');
    use Storable('thaw', 'nfreeze');
    use Socket;

    use aliased 'POEx::Role::Event';
    use aliased 'POEx::Role::ProxyEvent';
    use aliased 'MooseX::Method::Signatures::Meta::Method', 'MXMSMethod';
    use aliased 'POEx::ProxySession::Proxy';


    has subscriptions =>
    (
        traits      => [ 'Hash' ],
        isa         => HashRef[Dict[ meta => class_type('Moose::Meta::Class'), wheel => WheelID ]],
        lazy        => 1,
        default     => sub { {} },
        clearer     => 'clear_subscriptions',
        handles     => 
        {
            get_subscription        => 'get',
            set_subscription        => 'set',
            delete_subscription     => 'delete',
            count_subscriptions     => 'count',
            all_subscription_names  => 'keys',
            has_subscription        => 'exists',
        }
    );



    has publications =>
    (
        traits      => [ 'Hash' ],
        isa         => HashRef
        [
            Dict
            [
                methods => HashRef,
                wheel   => WheelID,
                alias   => SessionAlias,
            ]
        ],
        lazy        => 1,
        default     => sub { {} },
        clearer     => 'clear_publications',
        handles     => 
        {
            get_publication        => 'get',
            set_publication        => 'set',
            delete_publication     => 'delete',
            count_publications     => 'count',
            all_publication_names  => 'keys',
            has_publication        => 'exists',
        }
    );


    has active_connections =>
    (
        traits      => [ 'Hash' ],
        isa         => HashRef
        [
            Dict
            [
                remote_address  => Str,
                remote_port     => Int,
                tag             => Optional[Ref],
            ],
        ],
        lazy        => 1,
        default     => sub { {} },
        clearer     => 'clear_active_connections',
        handles     => 
        {
            get_active_connection        => 'get',
            set_active_connection        => 'set',
            delete_active_connection     => 'delete',
            count_active_connections     => 'count',
            all_active_connection_ids    => 'keys',
            has_active_connection        => 'exists',
        }
    );


    has unknown_message_event =>
    (
        is          => 'rw',
        isa         => Tuple[SessionID|SessionAlias, Str],
        predicate   => 'has_unknown_message_event',
    );


    has socket_error_event =>
    (
        is          => 'rw',
        isa         => Tuple[SessionID|SessionAlias, Str],
        predicate   => 'has_socket_error_event',
    );


    has connect_error_event =>
    (
        is          => 'rw',
        isa         => Tuple[SessionID|SessionAlias, Str],
        predicate   => 'has_socket_error_event',
    );


    method handle_inbound_data(ProxyMessage $data, WheelID $id) is Event {
        if($data->{type} eq 'result')
        {
            if($self->has_pending($data->{id}))
            {
                my $pending = $self->delete_pending($data->{id});
                $self->post($pending->{return_session}, $pending->{return_event}, $data, $id, $pending->{tag});
            }
            else
            {
                warn q|Received a result for something we didn't send out|;
                return;
            }
        }
        elsif ($data->{type} eq 'deliver')
        {
            if($self->has_publication($data->{to}))
            {
                my $payload = thaw($data->{payload});
                my $success = $self->post($data->{to}, $payload->{event}, @{ $payload->{args} });
                my $back = \${q|Unable to post '| . $payload->{event} . q|' to '| . $data->{to} . q|'|} if !$success;
                
                $self->send_result
                (
                    success     => $success, 
                    original    => $data,
                    payload     => defined($back) ? $back : \'', 
                    wheel_id    => $id
                );
            }
            else
            {
                warn q|Received a delivery for someone that isn't us|;

                $self->send_result
                (
                    success     => 0,
                    original    => $data,
                    payload     => \'Unknown recipient',
                    wheel_id    => $id,
                );

            }
        }
        else
        {
            if($self->has_unknown_message_event)
            {
                $self->post
                (
                    $self->unknown_message_event->[0],
                    $self->unknown_message_event->[1],
                    $data,
                    $id
                );
            }
        }
    }

    with 'POEx::Role::TCPClient';


    after _start(@args) is Event {
        $self->filter(POE::Filter::Reference->new());
    }


    around connect
    (
        Str :$remote_address, 
        Int :$remote_port, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {
        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        my $connect_tag = 
        {
            address         => $remote_address,
            port            => $remote_port,
            return_session  => defined($return_session) ? $return_session : $self->poe->sender->ID, 
            return_event    => $return_event,
            inner_tag       => $tag,
        };

        $orig->($self, remote_address => $remote_address, remote_port => $remote_port, tag => $connect_tag);
    }


    after handle_on_connect(GlobRef $socket, Str $address, Int $port, WheelID $id) is Event {
        if($self->has_connection_tag($id))
        {
            my $tag = $self->delete_connection_tag($id);
            
            $self->post
            (
                $tag->{return_session}, 
                $tag->{return_event},
                connection_id   => $self->last_wheel,
                remote_address  => inet_ntoa($address),
                remote_port     => $port,
                tag             => $tag->{inner_tag}
            );
            
            my $active_connection = 
            {
                remote_address  => $tag->{address},
                remote_port     => $tag->{port},
                tag             => $tag->{inner_tag},
            };

            $self->set_active_connection($id, $active_connection);
        }
        else
        {
            die "Unknown connection made. No connection tag associated with socket factory '$id'";
        }
    }

    after handle_socket_error(Str $action, Int $code, Str $message, WheelID $id) is Event {
        $self->delete_wheel($id);
        my $connection = $self->delete_active_connection($id);
        
        if($self->has_socket_error_event)
        {
            $self->post
            (
                @{$self->socket_error_event},
                %$connection,
            );
        }
    }



    after handle_connect_error(Str $action, Int $code, Str $message, WheelID $id) is Event {
        $self->delete_socket_factory($id);
        my $tag = $self->delete_connection_tag($id);

        if($self->has_connect_error_event)
        {
            $self->post
            (
                @{$self->connect_error_event},
                remote_address => $tag->{address},
                remote_port => $tag->{port},
                tag => $tag->{inner_tag},
            );
        }
    }

    method subscribe
    (
        WheelID :$connection_id,
        SessionAlias :$to_session, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {

        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        $return_session = defined($return_session) ? $return_session : $self->poe->sender->ID;
        
        my %data = 
        (
            id => -1,
            type => 'subscribe', 
            to => $to_session, 
            payload => nfreeze(\$to_session) 
        );
        
        $self->return_to_sender
        (
            message         => \%data, 
            wheel_id        => $connection_id, 
            return_session  => $self->ID, 
            return_event    => 'handle_on_subscribe',
            tag             =>
            {
                session         => $to_session,
                return_session  => $return_session,
                return_event    => $return_event,
                inner_tag       => $tag,
            }
        );
    }

    method handle_on_subscribe(ProxyMessage $data, WheelID $id, HashRef $tag) is Event {
        if($data->{success})
        {
            Proxy->new
            (
                parent_id => $self->ID,
                parent_startup => 'handle_on_proxy',
                args => [ $data, $id, $tag ],
                options => 
                { 
                    trace => exists($self->options->{trace}) && defined($self->options->{trace}) || 0, 
                    debug => exists($self->options->{debug}) && defined($self->options->{debug}) || 0,
                }
            );
        }
        else
        {
            $self->post
            (
               $tag->{return_session},
               $tag->{return_event},
               connection_id    => $id,
               success          => $data->{success},
               session_name     => $tag->{session},
               payload          => thaw($data->{payload}),
               tag              => $tag->{inner_tag},
            );
        }
    }

    method handle_on_proxy(SessionAlias $session_name, Object $meta, WheelID $id) is Event {
        $self->set_subscription($session_name, { meta => $meta, wheel => $id});
    }


    method unsubscribe
    (
        SessionAlias :$session_name, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {

        die "Unknown session '$session_name'"
            if not $self->has_subscription($session_name);
        
        my $session = to_Session($session_name);

        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        $return_session = defined($return_session) ? $return_session : $self->poe->sender->ID;
        
        if(!$session)
        {
            $self->delete_subscription($session_name);
            $self->post
            (
                $return_session, 
                $return_event,
                success         => 1,
                session_alias   => $session_name,
                tag             => $tag,
            );
            return;
        }
        
        my $meta = $session->meta;
        my $closure = sub { $self->delete_subscription($session_name) };
        $meta->add_after_method_modifer
        (
            '_stop', 
            sub 
            { 
                my $obj = shift;
                $obj->post
                (
                    $return_session , 
                    $return_event,
                    success         => 1,
                    session_alias   => $obj->alias,
                    tag             => $tag,
                );

                $closure->(); 
            } 
        );

        $self->post($session_name, 'shutdown');
    }


    method publish
    (
        WheelID :$connection_id, 
        SessionAlias :$session_alias, 
        DoesSessionInstantiation :$session, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {
        
        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        $return_session = defined($return_session) ? $return_session : $self->poe->sender->ID;

        my $meta = $session->meta;
        
        my $methods = {};
        foreach my $method ($meta->get_all_methods)
        {
            if($method->isa('Class::MOP::Method::Wrapped'))
            {
                my $orig = $method->get_original_method;
                if(!$orig->meta->isa('Moose::Meta::Class') || !$orig->meta->does_role(ProxyEvent))
                {
                    next;
                }
                else
                {
                    $method = $orig;
                }

            }
            elsif(!$method->meta->isa('Moose::Meta::Class') || !$method->meta->does_role(ProxyEvent))
            {
                next;
            }

            my $traits = [];

            foreach my $role ($method->meta->calculate_all_roles())
            {
                my $trait_args = [];
                foreach my $attr_name ($role->get_attribute_list)
                {
                    push(@$trait_args, [$attr_name, $method->$attr_name]);
                }
                push(@$traits, [$role->name, $trait_args]);
            }

            $methods->{$method->name} =  
            {
                signature => $method->signature,
                return_signature => $method->return_signature,
                traits => $traits,
            };
        }


        my %payload = 
        ( 
            session_name => defined($session->alias) ? $session->alias : $session->ID, 
            session_alias => $session_alias, 
            methods => $methods 
        ); 
        
        my $frozen;
        {
            local $SIG{__WARN__} = sub { };
            $frozen = nfreeze(\%payload);
        }
        my %data = 
        (
            id => -1,
            type => 'publish',
            payload => $frozen,
        );

        my %rtstag = 
        (
            %payload,
            return_session  => $return_session,
            return_event    => $return_event,
            inner_tag       => $tag,
        );

        $self->return_to_sender
        (
            message         => \%data, 
            wheel_id        => $connection_id, 
            return_session  => $self->ID, 
            return_event    => 'handle_on_publish', 
            tag             => \%rtstag
        );
    }

    method handle_on_publish(ProxyMessage $data, WheelID $id, HashRef $tag) is Event {
        if($data->{success})
        {
            $self->set_publication
            (
                $tag->{session_name},
                {
                    methods => $tag->{methods},
                    wheel   => $id,
                    alias   => $tag->{session_alias},
                }
            );
        }

        my %args = ( success => $data->{success}, session_alias => $tag->{session_alias} );
        $args{payload} = thaw($data->{payload}) if defined($data->{payload});

        $self->post
        (
            $tag->{return_session}, 
            $tag->{return_event},
            connection_id => $id,
            %args,
            tag => $tag->{inner_tag}
        );
    }


    method rescind
    (
        DoesSessionInstantiation :$session, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {

        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        $return_session = defined($return_session) ? $return_session : $self->poe->sender->ID;
        
        my $name = defined($session->alias) ? $session->alias : $session->ID;
        die "Session '$name' is not currently published"
            if not $self->has_publication($name);

        my $hash = $self->get_publication($name);
        
        $self->return_to_sender
        (
            message         => 
            {
                id => -1,
                type => 'rescind', 
                payload => nfreeze( { session_alias => $hash->{alias} } ) 
            }, 
            wheel_id        => $hash->{wheel},
            return_session  => $self->ID,
            return_event    => 'handle_on_rescind',
            tag             =>
            {
                session         => $name,
                return_session  => $return_session,
                return_event    => $return_event,
                inner_tag       => $tag,
            }
        );
    }

    method handle_on_rescind(ProxyMessage $data, WheelID $id, HashRef $tag) is Event {
        if($data->{success})
        {
            $self->delete_publication($tag->{session});
        }

        my %args = ( success => $data->{success}, session_name => $tag->{session} );
        $args{payload} = thaw($data->{payload}) if defined($data->{payload});

        $self->post
        (
            $tag->{return_session}, 
            $tag->{return_event},
            connection_id => $id,
            %args,
            tag => $tag->{inner_tag}
        );
    }


    method server_listing
    (
        WheelID :$connection_id, 
        SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?, 
        Str :$return_event,
        Ref :$tag?
    ) is Event {

        if(is_Session($return_session) or is_DoesSessionInstantiation($return_session))
        {
            $return_session = $return_session->ID;
        }

        $return_session = defined($return_session) ? $return_session : $self->poe->sender->ID;

        $self->return_to_sender
        (
            message         =>
            {
                id      => -1,
                type    => 'listing',
            },
            wheel_id        => $connection_id,
            return_session  => $self->ID,
            return_event    => 'handle_on_listing',
            tag             =>
            {
                return_session  => $return_session,
                return_event    => $return_event,
                inner_tag       => $tag,
            },
        );
    }

    method handle_on_listing(ProxyMessage $data, WheelID $id, HashRef $tag) is Event {

        my %args = ( success => $data->{success}, payload => thaw($data->{payload}) );
        $self->post
        (
            $tag->{return_session},
            $tag->{return_event},
            connection_id => $id,
            %args,
            tag => $tag->{inner_tag},
        );
    }
}
1;


=pod

=head1 NAME

POEx::ProxySession::Client - Proxies remote, published Sessions, or publishes, local Sessions for subscription

=head1 VERSION

version 1.102750

=head1 SYNOPSIS

    # on the publisher side
    class Foo 
    {
        with 'POEx::Role::SessionInstantiation';
        use aliased 'POEx::Role::Event';
        use aliased 'POEx::Role::ProxyEvent';
        
        # The event we want to expose
        method yarg() {  } is ProxyEvent
        
        after _start(@args) is Event
        {
            POEx::ProxySession::Client->new
            ( 
                alias   => 'Client',
                options => { trace => 1, debug => 1 },
            );

            $self->post
            (
                'Client', 
                'connect', 
                remote_address  => '127.0.0.1', 
                remote_port     => 56789,
                return_event    => 'post_connect'
            );
        }

        method post_connect
        (
            WheelID :$connection_id, 
            Str :$remote_address, 
            Int :$remote_port
        ) is Event
        {
            $self->post
            (
                'Client',
                'publish',
                connection_id   => $connection_id,
                session_alias   => 'FooSession',
                session         => $self,
                return_event    => 'check_publish'
            );
        }

        .....
    }

    # on the subscriber side
    class Bar with POEx::Role::SessionInstantiation
    {
        use aliased 'POEx::Role::Event';
        use aliased 'POEx::Role::ProxyEvent';
        
        after _start(@args) is Event
        {
            POEx::ProxySession::Client->new
            ( 
                alias   => 'Client',
                options => { trace => 1, debug => 1 },
            );

            $self->post
            (
                'Client', 
                'connect', 
                remote_address  => '127.0.0.1', 
                remote_port     => 56789,
                return_event    => 'post_connect'
            );
        }

        method post_connect
        (
            WheelID :$connection_id, 
            Str :$remote_address, 
            Int :$remote_port
        ) is Event
        {
            $self->post
            (
                'Client',
                'subscribe',
                connection_id   => $connection_id,
                to_session      => 'FooSession',
                return_event    => 'post_subscription',
            );
        }
        
        method post_subscription(Bool :$success, Str :$session_name, Ref :$payload?) is Event
        {
            if($success)
            {
                $self->post('FooSession', 'yarg');
            }
        }
    }

=head1 DESCRIPTION

POEx::ProxySession::Client enables remote sessions to interact with one another
via a system of subscription and publication. Client works via introspection on
Moose::Meta::Classes to build local, persistent sessions that proxy posts back
to the publisher with the attendant method signatures.

=head1 PUBLIC_ATTRIBUTES

=head2 subscriptions 

This attribute is used to store the various subscriptions made through the
client. It has no accessors beyond what are defined in the provides mechanism.

    handles     => 
    {
        get_subscription        => 'get',
        set_subscription        => 'set',
        delete_subscription     => 'delete',
        count_subscriptions     => 'count',
        all_subscription_names  => 'keys',
        has_subscription        => 'exists',
    }

Each instance of a subscription is actually stored as a hash with the following
keys:

    Subscription =>
    {
        meta    => isa Moose::Meta::Class,
        wheel   => isa WheelID
    }

=head2 active_connectios

The clients active connects are stored in this attribute. The following methods
are provided to access them:

    handles     => 
    {
        get_active_connection        => 'get',
        set_active_connection        => 'set',
        delete_active_connection     => 'delete',
        count_active_connections     => 'count',
        all_active_connection_ids    => 'keys',
        has_active_connection        => 'exists',
    }

Each connection is represented by a hashref with the following keys:

    Connection =>
    {
        remote_address  => isa Str,
        remote_port     => isa Int,
        tag             => isa Optional[Ref],
    }

=head2 unknown_message_event

    is: 'rw', isa: Tuple[SessionID|SessionAlias, Str]

Set this attribute to receive unknown messages that were sent to the client. 
This is handy for sending custom message types across the Server.

The event handler must have this signature:
(ProxyMessage $data, WheelID $id)

=head2 socket_error_event

    is: 'rw', isa: Tuple[SessionID|SessionAlias, Str]

When a socket error is received, the wheel is cleared, and the connection hash
is deleted from the active connection structure. Set this attribute to be
notified when a socket error occurs.

The event handler must have this signature:
(Str :$remote_address, Int :$remote_port, Ref :$tag?)

=head2 connect_error_event

    is: 'rw', isa: Tuple[SessionID|SessionAlias, Str]

When a connect error is received, the wheel is cleared, and the connection hash
is deleted from the active connection structure. Set this attribute to be
notified when a socket error occurs.

The event handler must have this signature:
(Str :$remote_address, Int :$remote_port, Ref :$tag?)

=head1 PUBLIC_METHODS

=head2 subscribe

    (WheelID :$connection_id,
    SessionAlias :$to_session,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag?) is Event

subscribe sends a message out to the server, and the handler receives the 
appropriate metadata and constructs a local, persistent session that proxies 
posts back to the publisher. Once the session is finished constructing itself
it will post a message to the provided return event.

The return event must have the following signature:
(WheelID :$connection_id, Bool :$success, SessionAlias :$session_name, Ref :$payload, Ref :$tag?)

Since subscription can fail, $success will indicate whether it succeeded or not
and if not $payload will be a scalar reference to a string explaining why.

Otherwise, if subscription was successful, $payload will contain the original
payload from the server containing the metadata.

=head2 unsubscribe

    (SessionAlias :$session_name,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag) is Event

To unsubscribe from a proxied session, use this method. This will destroy the 
session by removing its alias. Only pending events will keep the session alive.

If it happens such that the session no longer exists, the return event will be 
posted right away, other wise, _stop on the proxied session is advised to post
the return event.

The return event must have the following signature:
(Bool :$success, SessionAlias :$session_alias, Ref :$tag?)

=head2 publish

    (WheelID :$connection_id,
    SessionAlias :$session_alias,
    DoesSessionInstantiation :$session,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag?) is Event

This method will publish a particular session to the server, such that other 
clients can then subscribe.

The connection_id is required to know where to send the publish message. Keep
track of each connection_id received from connect() to know where publications
should happen. The session_alias argument is how the session should be 
addressed on the server. The alias will be used by subscribing clients.

Currently, only sessions that are composed of POEx::Role::SessionInstantiation
are supported and as such, a reference to a session that does that role is 
required to allow the proper introspection on the subscriber end.

To indicate which methods should be proxied, simply decorate them with the 
POEx::Role::ProxyEvent role. All other methods will be ignored in proxy 
creation.

The return event must have the following signature:
(WheelID :$connection_id, Bool :$success, SessionAlias :$session_alias, Ref :$payload?, Ref :$tag?)

Since publication can fail, $success will indicate whether it succeeded or not
and if not $payload will be a scalar reference to a string explaining why.

Otherwise, if publication was successful, $payload will contain the original
payload from the server containing the metadata.

=head2 rescind

    (DoesSessionInstantiation :$session,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag?) is Event

To take back a publication, use this method and pass it the session reference.

The return event must have the following signature:
(WheelID :$connection_id, Bool :$success, SessionAlias :$session_name, Ref :$payload?, Ref :$tag?)

Since rescinding can fail, $success will let you know if it did. And if it did,
$payload will be a reference a string explaining why. Otherwise, payload will
be undef.

=head2 server_listing

    (WheelID :$connection_id,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag?) is Event

server_listing will query a particular server for a list of all published 
sessions that it knows about. It returns it as an array of session aliases
suitable for subscription.

The return event must have the following signature:
(WheelID :$connection_id, Bool :$success, ArrayRef :$payload, Ref :$tag?)

=head1 PROTECTED_METHODS

=head2 handle_inbound_data

    (ProxyMessage $data, WheelID $id) is Event

Our implementation of handle_inbound_data expects a ProxyMessage as data. Here 
is where the handling and routing of messages lives. Only handles two types of
ProxyMessage: result, and deliver. For more information on ProxyMessage types,
see the POD in POEx::ProxySession::Types. If an unknown message type is
encountered and unknown_message_event is set, it will be delivered to there.

=head2 around connect

    (Str :$remote_address,
    Int :$remote_port,
    SessionAlias|SessionID|Session|DoesSessionInstantiation :$return_session?,
    Str :$return_event,
    Ref :$tag?) is Event

The connect method is advised to add additional parameters in the form of a
return session and return event to use once the connection has been 
established.

The return event will need the following signature:
(WheelID :$connection_id, Str :$remote_address, Int :$remote_port, Ref :tag?)

=head2 after handle_on_connect

    (GlobRef $socket, Str $address, Int $port, WheelID $id) is Event

handle_on_connect is advised to find the specified return session and event
and post the message with the paramters received from the socketfactory

=head2 after handle_socket_error

    (Str $action, Int $code, Str $message, WheelID $id) is Event

handle_socket_error is advised to clean up the active connection if an error
has occurred. The socket_error_event is delivered then with the connection
information if there is such an event.

=head2 after handle_connect_error

    (Str $action, Int $code, Str $message, WheelID $id) is Event

handle_connect_error is advised to clean up resources such as the socket
factory and the connection tag if there was a error connecting. The error along
with the tag information is delivered to the connect_error_event if it has been
defined.

=head1 PRIVATE_METHODS

=head2 after _start

    (@args) is Event

The _start method is advised to hardcode the filter to use as a 
POE::Filter::Reference instance.

=attrbute_public publications

This attribute is used to store all publications made through the client. It 
has no accessors beyond what are defined in the provides mechanism.

Each instance of a publication is stored as a hash with the following keys:

    Publication =>
    {
        methods         => isa HashRef,
        wheel           => isa WheelID,
        session_alias   => isa SessionAlias,
    }

=head1 CAVEATS

It should be noted that the transport mechanism makes use of Storable. That
means that all of the various end points in a spawling system need to use the
same version of Storable to make sure things serialize/deserialize correctly.

=head1 AUTHOR

Nicholas Perez <nperez@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Nicholas Perez.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__
