package POEx::ProxySession::Types;
our $VERSION = '0.092340';

use warnings;
use strict;
use 5.010;

#ABSTRACT: Types for use within the ProxySession environment

use MooseX::Types -declare => ['ProxyMessage'];
use MooseX::Types::Moose(':all');
use MooseX::Types::Structured('Dict', 'Optional');


subtype ProxyMessage,
    as Dict
    [
        type => Str,
        id => Int,
        payload => Optional[Str],
        to => Optional[Str],
        success => Optional[Bool],
    ],
    where 
    {
        my $hash = $_;
        given($hash->{type})
        {
            when('deliver')
            {
                return defined($hash->{to});
            }
            when('result')
            {
                return defined($hash->{success});
            }
            when('subscribe')
            {
                return defined($hash->{to});
            }
            when('publish')
            {
                return defined($hash->{payload});
            }
            when('rescind')
            {
                return defined($hash->{payload});
            }
            when('listing')
            {
                return 1;
            }
            default
            {
                # we do this so that this may be used as a base type
                return 1;
            }
        }
    };
        
1;



=pod

=head1 NAME

POEx::ProxySession::Types - Types for use within the ProxySession environment

=head1 VERSION

version 0.092340

=head1 Types

=head2 ProxyMessage

ProxyMessage is a Dict with the following structure:

    type => Str,
    id => Int,
    payload => Optional[Str],
    to => Optional[Str],
    success => Optional[Bool],

type can be any of the following: deliver, result, subscribe, publish, listing,
and rescind. Each type has some light validation. Deliver requires 'to' to be
set. Result requires 'success' to be set. Subscribe requires 'to'. Publish and
rescind both require 'payload' to be set. 

This type does not validate the contents of the payload.



=head1 DESCRIPTION

POEx::ProxySession::Types provides types for use within the ProxySession
environment that are self validating.

=head1 AUTHOR

  Nicholas Perez <nperez@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by Nicholas Perez.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut 



__END__
